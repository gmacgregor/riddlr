defmodule Riddlr.Games.RiddleSchedulerTest do
  use Riddlr.DataCase, async: true
  import Ecto.Query
  import Riddlr.GamesFixtures
  alias Riddlr.Games
  alias Riddlr.Games.RiddleScheduler

  describe "cancel_pending_jobs/1" do
    test "cancels all scheduled jobs for a riddle" do
      riddle = riddle_fixture(%{publish_status: "published", play_status: "closed"})
      live_date = DateTime.add(DateTime.utc_now(), 3600, :second)

      # Schedule the riddle (creates jobs)
      assert {:ok, _} = Games.schedule_riddle(riddle, live_date)

      # Verify jobs exist
      pending_jobs =
        Oban.Job
        |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(pending_jobs) > 0

      # Cancel them
      assert {:ok, cancelled_count} = RiddleScheduler.cancel_pending_jobs(riddle.id)
      assert cancelled_count > 0

      # Verify jobs are cancelled
      remaining_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(remaining_jobs) == 0
    end

    test "returns {:ok, 0} when no pending jobs exist" do
      riddle = riddle_fixture()
      assert {:ok, 0} = RiddleScheduler.cancel_pending_jobs(riddle.id)
    end
  end

  describe "reschedule_jobs/2" do
    test "cancels old jobs and creates new ones with updated live_date" do
      riddle = riddle_fixture(%{publish_status: "published", play_status: "closed"})
      original_live_date = DateTime.add(DateTime.utc_now(), 3600, :second)

      # Schedule the riddle
      assert {:ok, _} = Games.schedule_riddle(riddle, original_live_date)

      # Change live_date
      new_live_date = DateTime.add(DateTime.utc_now(), 7200, :second)

      assert {:ok, _count} = RiddleScheduler.reschedule_jobs(riddle.id, new_live_date)

      # Verify old jobs are cancelled
      old_jobs =
        Oban.Job
        |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.scheduled_at == ^DateTime.add(original_live_date, -300, :second))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(old_jobs) == 0

      # Verify new jobs scheduled at correct times
      ready_job =
        Oban.Job
        |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.one()

      assert ready_job.scheduled_at == DateTime.add(new_live_date, -300, :second)

      live_job =
        Oban.Job
        |> where([j], j.worker == "Riddlr.Workers.LiveRiddleTransitionWorker")
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.one()

      assert live_job.scheduled_at == new_live_date
    end
  end
end
