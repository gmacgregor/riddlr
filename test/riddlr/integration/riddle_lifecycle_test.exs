defmodule Riddlr.Integration.RiddleLifecycleTest do
  use Riddlr.DataCase, async: true
  import Riddlr.GamesFixtures
  alias Riddlr.Games
  import Ecto.Query

  describe "full riddle lifecycle" do
    test "riddle transitions through all states correctly" do
      # Start with draft riddle
      riddle =
        riddle_fixture(%{
          publish_status: "draft",
          play_status: "closed",
          live_date: DateTime.add(DateTime.utc_now(), 3600)
        })

      assert riddle.publish_status == "draft"
      assert riddle.play_status == "closed"

      # Step 1: Publish riddle and schedule -> should schedule workers
      {:ok, riddle} = Games.update_riddle(riddle, %{publish_status: "published"})
      {:ok, %{riddle: updated_riddle}} = Games.schedule_riddle(riddle, riddle.live_date)

      assert updated_riddle.play_status == "scheduled"

      # Verify jobs scheduled (ready + live)
      jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(jobs) == 2
      ready_job = Enum.find(jobs, &(&1.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker"))
      live_job = Enum.find(jobs, &(&1.worker == "Riddlr.Workers.LiveRiddleTransitionWorker"))
      assert ready_job != nil
      assert live_job != nil

      # Step 2: Change live_date -> should reschedule
      new_live_date = DateTime.add(DateTime.utc_now(), 7200)
      {:ok, riddle} = Games.update_riddle(riddle, %{live_date: new_live_date})

      updated_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(updated_jobs) == 2

      # Verify new scheduled times match new_live_date
      updated_ready_job =
        Enum.find(updated_jobs, &(&1.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker"))

      updated_live_job =
        Enum.find(updated_jobs, &(&1.worker == "Riddlr.Workers.LiveRiddleTransitionWorker"))

      expected_ready_time = DateTime.add(new_live_date, -riddle.ready_before_seconds, :second)

      assert DateTime.diff(updated_ready_job.scheduled_at, expected_ready_time, :second) <= 1
      assert DateTime.diff(updated_live_job.scheduled_at, new_live_date, :second) <= 1

      # Step 3: Move to draft -> should cancel all jobs
      {:ok, riddle} = Games.update_riddle(riddle, %{publish_status: "draft"})

      remaining_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(remaining_jobs) == 0

      # Step 4: Test custom cooldown - republish and move through states
      {:ok, riddle} =
        Games.update_riddle(riddle, %{
          publish_status: "published",
          archive_after_seconds: 600
        })

      # Schedule the riddle first (closed -> scheduled)
      future_live_date = DateTime.add(DateTime.utc_now(), 7200)
      {:ok, %{riddle: riddle}} = Games.schedule_riddle(riddle, future_live_date)

      # Move through the lifecycle using proper functions
      {:ok, riddle} = Games.transition(riddle.id, :ready)
      {:ok, riddle} = Games.transition(riddle.id, :live)

      # Now complete the riddle
      {:ok, _} = Games.transition(riddle.id, :completed)

      archive_job =
        Oban.Job
        |> where([j], j.worker == "Riddlr.Workers.ArchiveRiddleTransitionWorker")
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> Repo.one()

      # Verify 600-second delay
      expected_time = DateTime.add(DateTime.utc_now(), 600)
      assert DateTime.diff(archive_job.scheduled_at, expected_time, :second) < 5
    end

    test "zero cooldown archives immediately" do
      riddle =
        riddle_fixture(%{
          play_status: "closed",
          publish_status: "published",
          archive_after_seconds: 0
        })

      # Move through lifecycle: closed -> scheduled -> ready -> live
      future_live_date = DateTime.add(DateTime.utc_now(), 3600)
      {:ok, %{riddle: riddle}} = Games.schedule_riddle(riddle, future_live_date)
      {:ok, riddle} = Games.transition(riddle.id, :ready)
      {:ok, riddle} = Games.transition(riddle.id, :live)

      # Now complete the riddle
      {:ok, _} = Games.transition(riddle.id, :completed)

      archive_job =
        Oban.Job
        |> where([j], j.worker == "Riddlr.Workers.ArchiveRiddleTransitionWorker")
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> Repo.one()

      # Job should be available immediately (scheduled_at <= now)
      assert DateTime.compare(archive_job.scheduled_at, DateTime.utc_now()) in [:lt, :eq]
    end

    test "default cooldown is 180 seconds" do
      riddle =
        riddle_fixture(%{
          play_status: "closed",
          publish_status: "published"
        })

      # Verify default cooldown
      assert riddle.archive_after_seconds == 180

      # Move through lifecycle: closed -> scheduled -> ready -> live
      future_live_date = DateTime.add(DateTime.utc_now(), 3600)
      {:ok, %{riddle: riddle}} = Games.schedule_riddle(riddle, future_live_date)
      {:ok, riddle} = Games.transition(riddle.id, :ready)
      {:ok, riddle} = Games.transition(riddle.id, :live)

      # Complete the riddle
      {:ok, _} = Games.transition(riddle.id, :completed)

      archive_job =
        Oban.Job
        |> where([j], j.worker == "Riddlr.Workers.ArchiveRiddleTransitionWorker")
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> Repo.one()

      # Verify 3-minute delay (180 seconds)
      expected_time = DateTime.add(DateTime.utc_now(), 180)
      assert DateTime.diff(archive_job.scheduled_at, expected_time, :second) < 5
    end

    test "republishing after draft rollback works correctly" do
      # Start with scheduled riddle
      live_date = DateTime.add(DateTime.utc_now(), 3600)

      riddle =
        riddle_fixture(%{
          publish_status: "published",
          play_status: "closed",
          live_date: live_date
        })

      {:ok, %{riddle: riddle}} = Games.schedule_riddle(riddle, live_date)
      assert riddle.play_status == "scheduled"

      # Verify jobs exist
      initial_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(initial_jobs) == 2

      # Roll back to draft
      {:ok, riddle} = Games.update_riddle(riddle, %{publish_status: "draft"})
      assert riddle.publish_status == "draft"

      # Verify jobs are cancelled
      cancelled_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(cancelled_jobs) == 0

      # Republish with new live_date
      # First, reset to closed state so we can schedule again
      {:ok, riddle} = Games.update_riddle(riddle, %{play_status: "closed"})
      new_live_date = DateTime.add(DateTime.utc_now(), 5400)
      {:ok, riddle} = Games.update_riddle(riddle, %{publish_status: "published"})
      {:ok, %{riddle: riddle}} = Games.schedule_riddle(riddle, new_live_date)

      assert riddle.play_status == "scheduled"

      # Verify new jobs are created
      new_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Repo.all()

      assert length(new_jobs) == 2

      # Verify they're scheduled at the new time
      new_live_job =
        Enum.find(new_jobs, &(&1.worker == "Riddlr.Workers.LiveRiddleTransitionWorker"))

      assert DateTime.diff(new_live_job.scheduled_at, new_live_date, :second) <= 1
    end
  end
end
