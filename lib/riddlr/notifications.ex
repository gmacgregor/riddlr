defmodule Riddlr.Notifications do
  @moduledoc """
  Notifications: messages that tell a player a riddle is about to go live.

  Email only for now. The send flow has two steps, both Oban jobs on the
  `notifications` queue:

    1. Fan-out (`fan_out/2`) writes one `RiddleNotification` row per eligible
       player and queues one send job per new row.
    2. Send (`deliver/1`) checks the riddle and player again, sends the email
       and stamps `sent_at`.

  The unique row per riddle, player and channel is what stops a second email.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Riddlr.Accounts.User
  alias Riddlr.Clock
  alias Riddlr.Games.Riddle
  alias Riddlr.Mailer
  alias Riddlr.Notifications.{Email, RiddleNotification}
  alias Riddlr.Repo
  alias Riddlr.Workers.SendNotificationWorker

  # A riddle in any other Play status has no Live date ahead of it.
  @upcoming ["scheduled", "ready"]

  @unsubscribe_salt "unsubscribe notifications"

  @doc """
  Writes a Notification row for every player who wants one at `lead_time` and
  queues a send job for each **new** row.

  An eligible player has email notifications on, this lead time, an active
  account and a confirmed email. Rows that already exist are left alone, so
  running this twice sends nothing twice.

  Returns `{:ok, new_row_count}`, or `{:skip, reason}` when the riddle is gone
  or no longer upcoming.
  """
  @spec fan_out(integer(), :lobby_open | :min_30 | :min_60) ::
          {:ok, non_neg_integer()} | {:skip, String.t()} | {:error, term()}
  def fan_out(riddle_id, lead_time) do
    with {:ok, riddle} <- fetch_upcoming(riddle_id) do
      Multi.new()
      |> Multi.insert_all(:rows, RiddleNotification, eligible_rows(riddle, lead_time),
        on_conflict: :nothing,
        returning: [:id]
      )
      |> Multi.run(:send_jobs, fn _repo, %{rows: {_count, rows}} ->
        rows
        |> Enum.map(&SendNotificationWorker.new(%{"notification_id" => &1.id}))
        |> Oban.insert_all()
        |> then(&{:ok, &1})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{rows: {count, _rows}}} -> {:ok, count}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  # One query feeds the insert, so the rows land in a single statement.
  @spec eligible_rows(Riddle.t(), atom()) :: Ecto.Query.t()
  defp eligible_rows(riddle, lead_time) do
    now = Clock.utc_now() |> DateTime.truncate(:second)

    from u in User,
      where: u.notify_email == true,
      where: u.notification_lead_time == ^lead_time,
      where: u.account_status == ^:active,
      where: not is_nil(u.confirmed_at),
      select: %{
        riddle_id: type(^riddle.id, :integer),
        user_id: u.id,
        channel: type(^"email", :string),
        inserted_at: type(^now, :utc_datetime),
        updated_at: type(^now, :utc_datetime)
      }
  end

  @spec fetch_upcoming(integer()) :: {:ok, Riddle.t()} | {:skip, String.t()}
  defp fetch_upcoming(riddle_id) do
    case Repo.get(Riddle, riddle_id) do
      nil -> {:skip, "riddle #{riddle_id} not found"}
      %Riddle{publish_status: "published", play_status: s} = r when s in @upcoming -> {:ok, r}
      %Riddle{play_status: s} -> {:skip, "riddle #{riddle_id} is #{s}, not upcoming"}
    end
  end

  @doc """
  Deletes a riddle's Notifications that have not gone out yet, inside the
  caller's transaction. Unschedule calls this, so a later Schedule can notify
  those players again. A pending send job then finds no row and stops.
  """
  @spec drop_unsent(Ecto.Repo.t(), integer()) :: {:ok, non_neg_integer()}
  def drop_unsent(repo, riddle_id) do
    {count, _} =
      RiddleNotification
      |> where([n], n.riddle_id == ^riddle_id and is_nil(n.sent_at))
      |> repo.delete_all()

    {:ok, count}
  end

  @doc """
  Sends one Notification and stamps `sent_at`.

  Checks everything again first, because time passed since the fan-out. It
  skips when the row is gone or already sent, the riddle is no longer
  scheduled or ready, the Live date has passed, or the player stopped being
  eligible.

  Returns `{:ok, row}`, `{:skip, reason}`, or `{:error, reason}` when the mail
  provider fails (the caller may retry).

  ## Options

    * `:mailer_config` - overrides the `Riddlr.Mailer` config, e.g. to swap
      the adapter in tests.
  """
  @spec deliver(integer(), keyword()) ::
          {:ok, RiddleNotification.t()} | {:skip, String.t()} | {:error, term()}
  def deliver(notification_id, opts \\ []) do
    # The row lock stops two sends of one row overlapping. The share lock on
    # the riddle makes an Unschedule wait until this send ends, so a send that
    # passed the checks is never beaten by one. A crash after the provider
    # takes the mail but before COMMIT can still send twice on retry.
    Repo.transaction(fn ->
      now = Clock.utc_now()

      with {:ok, row} <- lock_unsent(notification_id),
           {:ok, riddle} <- lock_riddle(row.riddle_id),
           :ok <- check_riddle(riddle, now),
           :ok <- check_player(row.user),
           token = unsubscribe_token(row.user),
           email = Email.lobby_open(riddle, row.user, token, now),
           {:ok, _meta} <- Mailer.deliver(email, opts[:mailer_config] || []),
           {:ok, sent} <- mark_sent(row, now) do
        sent
      else
        {:skip, reason} -> Repo.rollback({:skip, reason})
        {:error, reason} -> Repo.rollback({:error, reason})
      end
    end)
    |> case do
      {:ok, sent} -> {:ok, sent}
      {:error, {:skip, reason}} -> {:skip, reason}
      {:error, {:error, reason}} -> {:error, reason}
    end
  end

  @spec lock_unsent(integer()) :: {:ok, RiddleNotification.t()} | {:skip, String.t()}
  defp lock_unsent(id) do
    RiddleNotification
    |> where([n], n.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:skip, "notification #{id} not found"}
      %RiddleNotification{sent_at: %DateTime{}} -> {:skip, "notification #{id} already sent"}
      row -> {:ok, Repo.preload(row, :user)}
    end
  end

  @spec lock_riddle(integer()) :: {:ok, Riddle.t()} | {:skip, String.t()}
  defp lock_riddle(id) do
    Riddle
    |> where([r], r.id == ^id)
    |> lock("FOR SHARE")
    |> Repo.one()
    |> case do
      nil -> {:skip, "riddle #{id} not found"}
      riddle -> {:ok, Repo.preload(riddle, :category)}
    end
  end

  @spec mark_sent(RiddleNotification.t(), DateTime.t()) ::
          {:ok, RiddleNotification.t()} | {:error, Ecto.Changeset.t()}
  defp mark_sent(row, now) do
    row
    |> Ecto.Changeset.change(sent_at: DateTime.truncate(now, :second))
    |> Repo.update()
  end

  @spec check_riddle(Riddle.t(), DateTime.t()) :: :ok | {:skip, String.t()}
  defp check_riddle(%Riddle{publish_status: "published", play_status: s} = riddle, now)
       when s in @upcoming do
    if DateTime.after?(riddle.live_date, now),
      do: :ok,
      else: {:skip, "riddle #{riddle.id} Live date has passed"}
  end

  defp check_riddle(%Riddle{} = riddle, _now),
    do: {:skip, "riddle #{riddle.id} is #{riddle.play_status}, not upcoming"}

  @spec check_player(User.t()) :: :ok | {:skip, String.t()}
  defp check_player(%User{
         notify_email: true,
         account_status: :active,
         confirmed_at: %DateTime{}
       }),
       do: :ok

  defp check_player(%User{id: id}), do: {:skip, "player #{id} no longer eligible"}

  @doc """
  A signed token that lets the holder turn off one player's email
  Notifications without logging in. It does not expire.
  """
  @spec unsubscribe_token(User.t()) :: String.t()
  def unsubscribe_token(%User{id: id}),
    do: Phoenix.Token.sign(RiddlrWeb.Endpoint, @unsubscribe_salt, id)

  @doc """
  Checks an unsubscribe token. Returns `{:ok, user_id}` or `{:error, :invalid}`.
  """
  @spec verify_unsubscribe_token(String.t()) :: {:ok, integer()} | {:error, :invalid}
  def verify_unsubscribe_token(token) when is_binary(token) do
    case Phoenix.Token.verify(RiddlrWeb.Endpoint, @unsubscribe_salt, token, max_age: :infinity) do
      {:ok, id} -> {:ok, id}
      {:error, _reason} -> {:error, :invalid}
    end
  end

  @doc """
  Turns off email Notifications for the player named in `token`.

  Returns `{:ok, user}` or `{:error, :invalid}` for a bad or unknown token.
  """
  @spec unsubscribe(String.t()) :: {:ok, User.t()} | {:error, :invalid}
  def unsubscribe(token) when is_binary(token) do
    with {:ok, id} <- verify_unsubscribe_token(token),
         %User{} = user <- Repo.get(User, id),
         {:ok, user} <- Riddlr.Accounts.update_user_notifications(user, %{notify_email: false}) do
      {:ok, user}
    else
      _ -> {:error, :invalid}
    end
  end
end
