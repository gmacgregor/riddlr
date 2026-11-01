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
  A new consent row for `user`, or `nil` when `changeset` does not change
  `notify_email`.
  """
  @spec for_email_change(User.t(), Ecto.Changeset.t()) :: t() | nil
  def for_email_change(%User{id: user_id}, changeset) do
    case Ecto.Changeset.fetch_change(changeset, :notify_email) do
      {:ok, true} -> %__MODULE__{user_id: user_id, channel: :email, action: :granted}
      {:ok, false} -> %__MODULE__{user_id: user_id, channel: :email, action: :withdrawn}
      :error -> nil
    end
  end
end
