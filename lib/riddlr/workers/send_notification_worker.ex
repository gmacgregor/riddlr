defmodule Riddlr.Workers.SendNotificationWorker do
  @moduledoc """
  Sends one Notification. The work lives in `Riddlr.Notifications.deliver/1`.

  A skip (riddle unscheduled, Live date passed, player opted out, already
  sent) cancels the job. A failed delivery returns an error, so Oban retries
  with its default backoff. A row another job is sending snoozes this one for
  a minute; the other job either stamps it, and this one then skips, or dies,
  and its claim goes stale so this one can send. After
  10 snoozes the job gives up as an error, which spends an attempt.
  """
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5

  alias Riddlr.Notifications

  @snooze_seconds 60
  @max_snoozes 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}} = job) do
    case Notifications.deliver(id) do
      {:ok, _notification} -> :ok
      {:skip, reason} -> {:cancel, reason}
      :claimed -> snooze(job)
      {:error, reason} -> {:error, reason}
    end
  end

  # A send that hangs must end before Notifications' claim goes stale, or a
  # second job could send while it is still running.
  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  # Snoozing does not spend an attempt, so the cap counts snoozes.
  @spec snooze(Oban.Job.t()) :: {:error, String.t()} | {:snooze, pos_integer()}
  defp snooze(%Oban.Job{meta: meta}) do
    if Map.get(meta, "snoozed", 0) >= @max_snoozes,
      do: {:error, "notification still claimed by another job"},
      else: {:snooze, @snooze_seconds}
  end
end
