defmodule Riddlr.Accounts.NotificationConsent do
  @moduledoc """
  One row each time a player turns a notification channel on or off: the
  proof of consent CASL asks for.

  The log only grows. There is no update or delete path; rows go only when
  their player is deleted. See `docs/adr/0001-notification-consent-log.md`.
  """
  use Ecto.Schema

  alias Riddlr.Accounts.User

  @type t :: %__MODULE__{}
  @type channel :: :email | :sms
  @type action :: :granted | :withdrawn

  schema "notification_consents" do
    belongs_to :user, User
    field :channel, Ecto.Enum, values: [:email, :sms]
    field :action, Ecto.Enum, values: [:granted, :withdrawn]

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  New consent rows for `user`: one per channel (`notify_email`,
  `notify_sms`) that `changeset` turns on or off. Empty when neither changes.
  """
  @spec for_changes(User.t(), Ecto.Changeset.t()) :: [t()]
  def for_changes(%User{id: user_id}, changeset) do
    for {field, channel} <- [notify_email: :email, notify_sms: :sms],
        {:ok, on?} <- [Ecto.Changeset.fetch_change(changeset, field)] do
      %__MODULE__{user_id: user_id, channel: channel, action: action(on?)}
    end
  end

  @spec action(boolean()) :: action()
  defp action(true), do: :granted
  defp action(false), do: :withdrawn
end
