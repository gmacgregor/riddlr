defmodule Riddlr.ObanMonitorTest do
  use Riddlr.DataCase, async: true

  alias Riddlr.ObanMonitor
  alias Riddlr.Workers.ArchiveRiddleTransitionWorker
  alias Riddlr.Workers.CompleteRiddleWorker

  @soon ~U[2099-06-15 16:00:00.000000Z]

  describe "stats/0" do
    test "counts jobs in total and by state, queue and worker" do
      job(CompleteRiddleWorker, 1, state: "scheduled")
      job(CompleteRiddleWorker, 2, state: "completed")
      job(ArchiveRiddleTransitionWorker, 1, state: "scheduled")

      stats = ObanMonitor.stats()

      assert stats.total == 3
      assert stats.by_state == %{"scheduled" => 2, "completed" => 1}
      assert stats.by_queue == %{"game_lifecycle" => 3}

      assert stats.by_worker == %{
               inspect(CompleteRiddleWorker) => 2,
               inspect(ArchiveRiddleTransitionWorker) => 1
             }
    end

    test "is all zeros with no jobs" do
      assert ObanMonitor.stats() == %{total: 0, by_state: %{}, by_queue: %{}, by_worker: %{}}
    end
  end

  describe "riddle_jobs/1" do
    test "lists only that riddle's jobs, soonest first" do
      later = job(CompleteRiddleWorker, 1, scheduled_at: DateTime.add(@soon, 60))
      sooner = job(ArchiveRiddleTransitionWorker, 1, scheduled_at: @soon)
      job(CompleteRiddleWorker, 2)

      assert [%{id: first}, %{id: second}] = ObanMonitor.riddle_jobs(1)
      assert [first, second] == [sooner.id, later.id]
    end
  end

  describe "upcoming_jobs/1" do
    test "lists scheduled jobs soonest first, up to the limit" do
      for n <- 3..1//-1, do: job(CompleteRiddleWorker, n, scheduled_at: DateTime.add(@soon, n))
      job(CompleteRiddleWorker, 4, state: "completed")

      assert [%{args: %{"riddle_id" => 1}}, %{args: %{"riddle_id" => 2}}] =
               ObanMonitor.upcoming_jobs(2)

      assert length(ObanMonitor.upcoming_jobs()) == 3
    end
  end

  describe "failed_jobs/1" do
    test "lists retryable and discarded jobs, latest attempt first" do
      old = job(CompleteRiddleWorker, 1, state: "retryable", attempted_at: @soon)
      new = job(CompleteRiddleWorker, 2, state: "discarded", attempted_at: DateTime.add(@soon, 1))
      job(CompleteRiddleWorker, 3, state: "completed", attempted_at: DateTime.add(@soon, 2))

      assert [%{id: first}, %{id: second}] = ObanMonitor.failed_jobs()
      assert [first, second] == [new.id, old.id]
      assert [%{id: ^first}] = ObanMonitor.failed_jobs(1)
    end
  end

  # Inserts a job for `riddle_id`, then sets the given columns directly.
  @spec job(module(), integer(), keyword()) :: Oban.Job.t()
  defp job(worker, riddle_id, fields \\ []) do
    job = Oban.insert!(worker.new(%{riddle_id: riddle_id}, scheduled_at: @soon))
    fields = Keyword.put_new(fields, :state, "scheduled")

    {1, [job]} =
      Oban.Job
      |> where(id: ^job.id)
      |> select([j], j)
      |> Repo.update_all(set: fields)

    job
  end
end
