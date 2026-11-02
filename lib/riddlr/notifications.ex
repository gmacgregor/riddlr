defmodule Riddlr.Notifications do
  @moduledoc """
  Notifications: messages that tell a player a riddle is about to go live.

  Sent by email, by text, or both. The send flow has two steps, both Oban
  jobs on the `notifications` queue:

    1. Fan-out (`fan_out/3`) writes one `RiddleNotification` row per eligible
       player and channel, and queues one send job per new row.
    2. Send (`deliver/1`) checks the riddle and player again, claims the
       row, sends the email or text and stamps `sent_at`.

  The unique row per riddle, player and channel, and the claim on it, are
  what stop a second send. Delivery is at least once: a job that dies after
  the provider took the message but before the stamp leaves a claim that
  goes stale, and a later job sends again.

  No database connection is held while the provider is called, so Unschedule
  does not wait for a send in flight: a send that passed its checks can still
  go out just after the riddle is unscheduled.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Riddlr.Accounts.User
  alias Riddlr.Clock
  alias Riddlr.Games.Riddle
  alias Riddlr.Mailer
  alias Riddlr.Notifications.{Email, RiddleNotification, Text}
  alias Riddlr.SMS
  alias Riddlr.Repo
  alias Riddlr.Workers.{NotificationFanOutWorker, SendNotificationWorker}

  # A riddle in any other Play status has no Live date ahead of it.
  @upcoming ["scheduled", "ready"]

  # Lead times tied to the clock, not to the Lobby opening, and how many
  # seconds before the Live date each one sends. Keys are strings, as they
  # appear in job args.
  @timed_lead_times %{"min_30" => 30 * 60, "min_60" => 60 * 60}

  @unsubscribe_salt "unsubscribe notifications"

  # A claim older than this belongs to a send job that died; another job may
  # take the row over. Longer than SendNotificationWorker's timeout.
  @claim_ttl_seconds 5 * 60

  # Postgres caps one statement at 65,535 bound parameters, and each send job
  # row binds 9, so one Oban.insert_all fails above ~7,200 jobs.
  @send_job_chunk 2_000

  @doc """
  Replaces a riddle's 30 min and 1 hour fan-out jobs. Schedule and Reschedule
  call this inside their transaction, so the cancel and the insert commit
  with the riddle save or not at all.

  Cancels any pending ones, then queues one per lead time, due that long
  before the Live date. A send moment already past is due at once. A Live
  date already past queues none: no one should hear about a riddle that has
  gone live. Rows already written stay, so a player already notified gets
  nothing more.
  """
  @spec replace_timed_fan_outs(Ecto.Repo.t(), Riddle.t()) :: {:ok, [Oban.Job.t()]}
  def replace_timed_fan_outs(repo, %Riddle{id: id, live_date: live_date}) do
    Oban.Job
    |> where([j], j.state in ["available", "scheduled", "retryable"])
    |> where([j], j.worker == ^inspect(NotificationFanOutWorker))
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(id)))
    |> where([j], fragment("?->>'lead_time'", j.args) in ^Map.keys(@timed_lead_times))
    |> repo.update_all(set: [state: "cancelled", cancelled_at: Clock.utc_now()])

    now = Clock.utc_now()

    jobs =
      for {lead_time, seconds} <- @timed_lead_times, DateTime.after?(live_date, now) do
        send_at = DateTime.add(live_date, -seconds, :second)
        opts = if DateTime.after?(send_at, now), do: [scheduled_at: send_at], else: []

        %{"riddle_id" => id, "lead_time" => lead_time}
        |> NotificationFanOutWorker.new(opts)
        |> repo.insert!()
      end

    {:ok, jobs}
  end

  @doc """
  Writes a Notification row for every player who wants one at `lead_time` and
  queues a send job for each **new** row.

  An eligible player has this lead time, an active account, and per channel:
  email on with a confirmed email, or Text on with a confirmed number. A
  player with both gets one row per channel. Rows that already exist are left alone, so
  running this twice sends nothing twice.

  Send jobs go in batches of `:chunk_size` (default #{@send_job_chunk}), all
  in the same transaction.

  Returns `{:ok, new_row_count}`, or `{:skip, reason}` when the riddle is gone
  or no longer upcoming.
  """
  @spec fan_out(integer(), :lobby_open | :min_30 | :min_60, keyword()) ::
          {:ok, non_neg_integer()} | {:skip, String.t()} | {:error, term()}
  def fan_out(riddle_id, lead_time, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @send_job_chunk)

    # The share lock on the riddle makes a Reschedule or Unschedule wait until
    # this fan-out commits, and makes this fan-out wait for theirs. Without it,
    # rows written after an Unschedule's `drop_unsent/2` would stay unsent and
    # block a later Schedule from notifying those players.
    Multi.new()
    |> Multi.run(:riddle, fn _repo, _changes -> lock_upcoming(riddle_id) end)
    |> insert_rows(:email, lead_time)
    |> insert_rows(:sms, lead_time)
    |> Multi.run(:send_jobs, fn _repo, %{email: {_, email_rows}, sms: {_, sms_rows}} ->
      (email_rows ++ sms_rows)
      |> Enum.map(&SendNotificationWorker.new(%{"notification_id" => &1.id}))
      |> Enum.chunk_every(chunk_size)
      |> Enum.flat_map(&Oban.insert_all/1)
      |> then(&{:ok, &1})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{email: {email_count, _}, sms: {sms_count, _}}} -> {:ok, email_count + sms_count}
      {:error, :riddle, {:skip, reason}, _changes} -> {:skip, reason}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  # Adds one channel's rows under the step named for the channel. One query
  # feeds the insert, so the rows land in a single statement that binds a few
  # parameters however many players match; it needs no chunks.
  @spec insert_rows(Multi.t(), RiddleNotification.channel(), atom()) :: Multi.t()
  defp insert_rows(multi, channel, lead_time) do
    Multi.insert_all(
      multi,
      channel,
      RiddleNotification,
      fn %{riddle: riddle} -> eligible_rows(riddle, lead_time, channel) end,
      on_conflict: :nothing,
      returning: [:id]
    )
  end

  @spec eligible_rows(Riddle.t(), atom(), RiddleNotification.channel()) :: Ecto.Query.t()
  defp eligible_rows(riddle, lead_time, channel) do
    now = Clock.utc_now() |> DateTime.truncate(:second)

    from(u in User,
      where: u.notification_lead_time == ^lead_time,
      where: u.account_status == ^:active,
      select: %{
        riddle_id: type(^riddle.id, :integer),
        user_id: u.id,
        channel: type(^Atom.to_string(channel), :string),
        inserted_at: type(^now, :utc_datetime),
        updated_at: type(^now, :utc_datetime)
      }
    )
    |> wants(channel)
  end

  @spec wants(Ecto.Query.t(), RiddleNotification.channel()) :: Ecto.Query.t()
  defp wants(query, :email),
    do: where(query, [u], u.notify_email == true and not is_nil(u.confirmed_at))

  defp wants(query, :sms),
    do: where(query, [u], u.notify_sms == true and not is_nil(u.phone_confirmed_at))

  @spec lock_upcoming(integer()) :: {:ok, Riddle.t()} | {:error, {:skip, String.t()}}
  defp lock_upcoming(riddle_id) do
    Riddle
    |> where([r], r.id == ^riddle_id)
    |> lock("FOR SHARE")
    |> Repo.one()
    |> case do
      nil ->
        {:error, {:skip, "riddle #{riddle_id} not found"}}

      %Riddle{publish_status: "published", play_status: s} = r when s in @upcoming ->
        {:ok, r}

      %Riddle{play_status: s} ->
        {:error, {:skip, "riddle #{riddle_id} is #{s}, not upcoming"}}
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

  Then it claims the row by setting `sending_at`, sends with no transaction
  open, and stamps `sent_at`. A row another job claimed less than
  #{div(@claim_ttl_seconds, 60)} minutes ago is left alone. If the provider
  fails, the claim is released so a retry can send. If the row was deleted
  while the message went out (Unschedule), the stamp finds nothing and the
  send still counts.

  Returns `{:ok, row}`, `{:skip, reason}`, `:claimed` when another job holds
  the row, or `{:error, reason}` when the mail or SMS provider fails (the
  caller may retry).

  ## Options

    * `:mailer_config` - overrides the `Riddlr.Mailer` config, e.g. to swap
      the adapter in tests.
  """
  @spec deliver(integer(), keyword()) ::
          {:ok, RiddleNotification.t()} | {:skip, String.t()} | :claimed | {:error, term()}
  def deliver(notification_id, opts \\ []) do
    now = Clock.utc_now()

    with {:ok, row} <- fetch_unsent(notification_id),
         {:ok, riddle} <- fetch_riddle(row.riddle_id),
         :ok <- check_riddle(riddle, now),
         :ok <- check_player(row.user, row.channel),
         {:ok, claimed_at} <- claim(row, now),
         :ok <- send_or_release(row, riddle, now, claimed_at, opts) do
      {:ok, stamp_sent(row, now)}
    end
  end

  @spec fetch_unsent(integer()) :: {:ok, RiddleNotification.t()} | {:skip, String.t()}
  defp fetch_unsent(id) do
    case Repo.get(RiddleNotification, id) do
      nil -> {:skip, "notification #{id} not found"}
      %RiddleNotification{sent_at: %DateTime{}} -> {:skip, "notification #{id} already sent"}
      row -> {:ok, Repo.preload(row, :user)}
    end
  end

  @spec fetch_riddle(integer()) :: {:ok, Riddle.t()} | {:skip, String.t()}
  defp fetch_riddle(id) do
    case Repo.get(Riddle, id) do
      nil -> {:skip, "riddle #{id} not found"}
      riddle -> {:ok, Repo.preload(riddle, :category)}
    end
  end

  # One UPDATE takes the row only if it is unsent and unclaimed, or its claim
  # is stale, so two jobs never both win it.
  @spec claim(RiddleNotification.t(), DateTime.t()) :: {:ok, DateTime.t()} | :claimed
  defp claim(%RiddleNotification{id: id}, now) do
    claimed_at = DateTime.truncate(now, :second)
    stale = DateTime.add(claimed_at, -@claim_ttl_seconds, :second)

    RiddleNotification
    |> where([n], n.id == ^id and is_nil(n.sent_at))
    |> where([n], is_nil(n.sending_at) or n.sending_at < ^stale)
    |> Repo.update_all(set: [sending_at: claimed_at])
    |> case do
      {1, _} -> {:ok, claimed_at}
      {0, _} -> :claimed
    end
  end

  @spec send_or_release(
          RiddleNotification.t(),
          Riddle.t(),
          DateTime.t(),
          DateTime.t(),
          keyword()
        ) :: :ok | {:error, term()}
  defp send_or_release(row, riddle, now, claimed_at, opts) do
    case send_message(row, riddle, now, opts) do
      :ok ->
        :ok

      {:error, reason} ->
        RiddleNotification
        |> where([n], n.id == ^row.id and n.sending_at == ^claimed_at)
        |> Repo.update_all(set: [sending_at: nil])

        {:error, reason}
    end
  end

  @spec stamp_sent(RiddleNotification.t(), DateTime.t()) :: RiddleNotification.t()
  defp stamp_sent(row, now) do
    sent_at = DateTime.truncate(now, :second)

    RiddleNotification
    |> where([n], n.id == ^row.id and is_nil(n.sent_at))
    |> Repo.update_all(set: [sent_at: sent_at, sending_at: nil])

    %{row | sent_at: sent_at, sending_at: nil}
  end

  # The number is read here only, from the loaded player, and goes no further
  # than the SMS adapter.
  @spec send_message(RiddleNotification.t(), Riddle.t(), DateTime.t(), keyword()) ::
          :ok | {:error, term()}
  defp send_message(%RiddleNotification{channel: :email, user: user}, riddle, now, opts) do
    email = Email.notification(riddle, user, unsubscribe_token(user), now)

    case Mailer.deliver(email, opts[:mailer_config] || []) do
      {:ok, _meta} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_message(%RiddleNotification{channel: :sms, user: user}, riddle, now, _opts),
    do: riddle |> Text.notification(user, now) |> SMS.deliver()

  @spec check_riddle(Riddle.t(), DateTime.t()) :: :ok | {:skip, String.t()}
  defp check_riddle(%Riddle{publish_status: "published", play_status: s} = riddle, now)
       when s in @upcoming do
    if DateTime.after?(riddle.live_date, now),
      do: :ok,
      else: {:skip, "riddle #{riddle.id} Live date has passed"}
  end

  defp check_riddle(%Riddle{} = riddle, _now),
    do: {:skip, "riddle #{riddle.id} is #{riddle.play_status}, not upcoming"}

  @spec check_player(User.t(), RiddleNotification.channel()) :: :ok | {:skip, String.t()}
  defp check_player(
         %User{notify_email: true, account_status: :active, confirmed_at: %DateTime{}},
         :email
       ),
       do: :ok

  defp check_player(
         %User{notify_sms: true, account_status: :active, phone_confirmed_at: %DateTime{}},
         :sms
       ),
       do: :ok

  defp check_player(%User{id: id}, _channel), do: {:skip, "player #{id} no longer eligible"}

  @doc """
  Whole minutes from `now` to the riddle's Live date, rounded up, so a send a
  few seconds late still says the full lead time. At least 1.
  """
  @spec minutes_left(Riddle.t(), DateTime.t()) :: pos_integer()
  def minutes_left(%Riddle{live_date: live_date}, now) do
    seconds = DateTime.diff(live_date, now, :second)
    max(div(seconds + 59, 60), 1)
  end

  @doc """
  Sends the one text that confirms a player turned Text on. Skips when Text
  is off again, the number is gone, or the account is not active.

  Returns `:ok`, `{:skip, reason}`, or `{:error, reason}` when the SMS
  provider fails (the caller may retry).
  """
  @spec deliver_sms_confirmation(integer()) :: :ok | {:skip, String.t()} | {:error, term()}
  def deliver_sms_confirmation(user_id) do
    with %User{} = user <- Repo.get(User, user_id),
         :ok <- check_player(user, :sms) do
      user |> Text.confirmation() |> SMS.deliver()
    else
      nil -> {:skip, "player #{user_id} not found"}
      {:skip, reason} -> {:skip, reason}
    end
  end

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
