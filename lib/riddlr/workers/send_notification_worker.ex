defmodule Riddlr.Workers.SendNotificationWorker do
  @moduledoc """
  Sends one Notification. The work lives in `Riddlr.Notifications.deliver/1`.

  A skip (riddle unscheduled, Live date passed, player opted out, already
  sent) cancels the job. A failed delivery returns an error, so Oban retries
  with its default backoff.
  """
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5

  alias Riddlr.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    case Notifications.deliver(id) do
      {:ok, _notification} -> :ok
      {:skip, reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
