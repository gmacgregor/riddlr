defmodule Riddlr.Workers.SendSmsConfirmationWorker do
  @moduledoc """
  Sends the one text that confirms a player turned Text on. Queued in the
  same transaction as the opt-in. Args hold the player id only, never the
  number. The work lives in `Riddlr.Notifications.deliver_sms_confirmation/1`.
  """
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    # A quick off-and-on again while a text waits sends one, not two.
    unique: [period: :infinity, keys: [:user_id], states: [:available, :scheduled, :retryable]]

  alias Riddlr.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Notifications.deliver_sms_confirmation(user_id) do
      :ok -> :ok
      {:skip, reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
