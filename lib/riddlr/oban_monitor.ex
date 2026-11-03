defmodule Riddlr.ObanMonitor do
  @moduledoc """
  Reads the Oban jobs table, for use from IEx.

      # Counts by state, queue and worker
      Riddlr.ObanMonitor.stats()

      # The jobs for one riddle
      Riddlr.ObanMonitor.riddle_jobs(123)

      # What runs next
      Riddlr.ObanMonitor.upcoming_jobs()

      # What failed
      Riddlr.ObanMonitor.failed_jobs()
  """

  import Ecto.Query
  alias Riddlr.Repo

  @doc "Counts every job, and counts them by state, by queue and by worker."
  @spec stats() :: %{
          total: non_neg_integer(),
          by_state: %{String.t() => pos_integer()},
          by_queue: %{String.t() => pos_integer()},
          by_worker: %{String.t() => pos_integer()}
        }
  def stats do
    by_state = count_by(:state)

    %{
      total: by_state |> Map.values() |> Enum.sum(),
      by_state: by_state,
      by_queue: count_by(:queue),
      by_worker: count_by(:worker)
    }
  end

  # Counts in the database, so stats never loads every job into memory.
  @spec count_by(:state | :queue | :worker) :: %{String.t() => pos_integer()}
  defp count_by(field) do
    from(j in Oban.Job, group_by: field(j, ^field), select: {field(j, ^field), count(j.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Lists the jobs whose args name `riddle_id`, soonest first."
  @spec riddle_jobs(integer()) :: [map()]
  def riddle_jobs(riddle_id) do
    Repo.all(
      from j in Oban.Job,
        where: fragment("? @> ?", j.args, type(^%{"riddle_id" => riddle_id}, :map)),
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

  @doc "Lists up to `limit` scheduled jobs, soonest first."
  @spec upcoming_jobs(pos_integer()) :: [map()]
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

  @doc "Lists up to `limit` retryable or discarded jobs, latest attempt first."
  @spec failed_jobs(pos_integer()) :: [map()]
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
