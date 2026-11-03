defmodule Riddlr.Accounts.NotificationPreferences do
  @moduledoc """
  A player's Notification choices: which channels they want, how long before
  a riddle goes live, and who gets each fan-out.

  Every channel turned on or off logs a `Riddlr.Accounts.NotificationConsent`
  row in the same transaction as the save. `Riddlr.Accounts` delegates its
  notification functions here.
  """

  import Ecto.Query, warn: false

  alias Riddlr.Accounts
  alias Riddlr.Accounts.{NotificationConsent, User}
  alias Riddlr.Repo
  alias Riddlr.Workers.SendSmsConfirmationWorker

  @doc """
  Returns a changeset for the user's notification choices.
  """
  @spec change_user_notifications(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_notifications(%User{} = user, attrs \\ %{}) do
    User.notification_changeset(user, attrs)
  end

  @doc """
  Saves the user's notification choices. An email on/off change also logs a
  consent row in the same transaction.
  """
  @spec update_user_notifications(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_notifications(%User{id: id}, attrs) do
    save_with_consent(
      fn ->
        id
        |> Accounts.lock_user!()
        |> User.notification_changeset(attrs)
      end,
      &Repo.update/1
    )
  end

  @typedoc "A way to reach a player with a Notification."
  @type notification_channel :: :email | :sms

  @doc """
  Returns a query for the players who want a Notification `lead_time` before
  a riddle goes live on `channel`.

  An eligible player has this lead time, an active account, and for email:
  email on with a confirmed email, or for `:sms`: Text on with a confirmed
  number. `notifiable?/2` applies the same rules to one loaded player.
  """
  @spec notification_recipients_query(atom(), notification_channel()) :: Ecto.Query.t()
  def notification_recipients_query(lead_time, channel) do
    from(u in User,
      where: u.notification_lead_time == ^lead_time,
      where: u.account_status == ^:active
    )
    |> wants_channel(channel)
  end

  @spec wants_channel(Ecto.Query.t(), notification_channel()) :: Ecto.Query.t()
  defp wants_channel(query, :email),
    do: where(query, [u], u.notify_email == true and not is_nil(u.confirmed_at))

  defp wants_channel(query, :sms),
    do: where(query, [u], u.notify_sms == true and not is_nil(u.phone_confirmed_at))

  @doc """
  Whether the player may get a Notification on `channel` now. The lead time
  is not checked: a player who changed it after the fan-out still gets the
  one already queued.
  """
  @spec notifiable?(User.t(), notification_channel()) :: boolean()
  def notifiable?(
        %User{notify_email: true, account_status: :active, confirmed_at: %DateTime{}},
        :email
      ),
      do: true

  def notifiable?(
        %User{notify_sms: true, account_status: :active, phone_confirmed_at: %DateTime{}},
        :sms
      ),
      do: true

  def notifiable?(%User{}, _channel), do: false

  @typedoc "What a user save returns."
  @type save_result :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Builds the changeset and saves the user inside one transaction, and logs
  each channel turned on or off. Building inside the transaction lets
  callers lock and read the stored row first, so two saves at once cannot
  both log the same change.
  """
  @spec save_with_consent((-> Ecto.Changeset.t()), (Ecto.Changeset.t() -> save_result())) ::
          save_result()
  def save_with_consent(build_changeset, save) do
    Repo.transaction(fn ->
      changeset = build_changeset.()

      with {:ok, user} <- save.(changeset) do
        log_channel_changes(user, changeset)
        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Inside the caller's transaction: logs one consent row per channel turned
  on or off, and queues the confirmation text when Text turns on.
  """
  @spec log_channel_changes(User.t(), Ecto.Changeset.t()) :: :ok
  def log_channel_changes(user, changeset) do
    user
    |> NotificationConsent.for_changes(changeset)
    |> Enum.each(&Repo.insert!/1)

    if Ecto.Changeset.get_change(changeset, :notify_sms) == true,
      do: Oban.insert!(SendSmsConfirmationWorker.new(%{"user_id" => user.id}))

    :ok
  end
end
