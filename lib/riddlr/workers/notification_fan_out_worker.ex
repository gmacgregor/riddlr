defmodule Riddlr.Workers.NotificationFanOutWorker do
  @moduledoc """
  Turns one riddle and one Notification lead time into one send job per
  eligible player. The work lives in `Riddlr.Notifications.fan_out/2`.

  Unique only while pending: a fan-out that already ran must not block the
  one a later Schedule queues. Running twice is safe; the rows stop repeats.
  """
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:riddle_id, :lead_time], states: :incomplete]

  alias Riddlr.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"riddle_id" => riddle_id, "lead_time" => lead_time}}) do
    case Notifications.fan_out(riddle_id, String.to_existing_atom(lead_time)) do
      {:ok, _count} -> :ok
      {:skip, reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
