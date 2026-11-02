defmodule Riddlr.Notifications.RiddleNotification do
  @moduledoc """
  One Notification: a riddle, a player and a channel. At most one per trio.

  `sent_at` stays nil until the message goes out.
  """

  use Ecto.Schema

  @type channel :: :email | :sms

  @type t :: %__MODULE__{
          id: integer() | nil,
          riddle_id: integer() | nil,
          user_id: integer() | nil,
          channel: channel() | nil,
          sent_at: DateTime.t() | nil
        }

  schema "riddle_notifications" do
    field :channel, Ecto.Enum, values: [:email, :sms]
    field :sent_at, :utc_datetime

    belongs_to :riddle, Riddlr.Games.Riddle
    belongs_to :user, Riddlr.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
