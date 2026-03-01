defmodule Riddlr.ObanMonitor do
  @doc """
  IEx usage:

  # Get overall stats
  Riddlr.ObanMonitor.stats()

  # See jobs for a specific riddle
  Riddlr.ObanMonitor.riddle_jobs(123)

  # See what's coming up next
  Riddlr.ObanMonitor.upcoming_jobs()

  # Check for failures
  Riddlr.ObanMonitor.failed_jobs()

  """
  import Ecto.Query
  alias Riddlr.Repo

  def stats do
    jobs = Repo.all(Oban.Job)

    %{
      total: length(jobs),
      by_state: Enum.frequencies_by(jobs, & &1.state),
      by_queue: Enum.frequencies_by(jobs, & &1.queue),
      by_worker: Enum.frequencies_by(jobs, & &1.worker)
    }
  end

  def riddle_jobs(riddle_id) do
    Repo.all(
      from j in Oban.Job,
        where: fragment("args->>'riddle_id' = ?", ^to_string(riddle_id)),
        order_by: [asc: j.scheduled_at],
        select: %{
          id: j.id,
          worker: j.worker,
          state: j.state,
          scheduled_at: j.scheduled_at,
          attempted_at: j.attempted_at,
          completed_at: j.completed_at
        }
    )
  end

  def upcoming_jobs(limit \\ 10) do
    Repo.all(
      from j in Oban.Job,
        where: j.state == "scheduled",
        order_by: [asc: j.scheduled_at],
        limit: ^limit,
        select: %{
          worker: j.worker,
          scheduled_at: j.scheduled_at,
          args: j.args
        }
    )
  end

  def failed_jobs(limit \\ 10) do
    Repo.all(
      from j in Oban.Job,
        where: j.state in ["retryable", "discarded"],
        order_by: [desc: j.attempted_at],
        limit: ^limit,
        select: %{
          id: j.id,
          worker: j.worker,
          errors: j.errors,
          attempt: j.attempt,
          max_attempts: j.max_attempts,
          attempted_at: j.attempted_at
        }
    )
  end
end
