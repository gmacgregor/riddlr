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
          live_date: future(3600)
        })

      assert riddle.publish_status == "draft"
      assert riddle.play_status == "closed"

      # Step 1: Publishing a riddle with a future live date schedules it
      {:ok, riddle} = Games.save_riddle(riddle, %{"publish_status" => "published"})

      assert riddle.play_status == "scheduled"
      assert [ready_job, live_job] = ordered_pending_jobs(riddle.id)
      assert ready_job.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker"
      assert live_job.worker == "Riddlr.Workers.LiveRiddleTransitionWorker"

      # Step 2: Change live_date -> should reschedule
      new_live_date = future(7200)
      {:ok, riddle} = Games.save_riddle(riddle, %{"live_date" => new_live_date})

      assert [updated_ready_job, updated_live_job] = ordered_pending_jobs(riddle.id)
      assert updated_ready_job.id != ready_job.id
      assert updated_live_job.id != live_job.id

      expected_ready_time = DateTime.add(new_live_date, -riddle.ready_before_seconds, :second)
      assert DateTime.compare(updated_ready_job.scheduled_at, expected_ready_time) == :eq
      assert DateTime.compare(updated_live_job.scheduled_at, new_live_date) == :eq

      # Step 3: Move to draft -> should cancel all jobs
      {:ok, riddle} = Games.save_riddle(riddle, %{"publish_status" => "draft"})

      assert riddle.play_status == "closed"
      assert ordered_pending_jobs(riddle.id) == []

      # Step 4: Republish with a custom cooldown, then run the riddle to completion
      {:ok, riddle} =
        Games.save_riddle(riddle, %{
          "publish_status" => "published",
          "archive_after_seconds" => 600
        })

      assert riddle.play_status == "scheduled"

      {:ok, riddle} = Games.transition(riddle.id, :ready)
      {:ok, riddle} = Games.transition(riddle.id, :live)
      {:ok, _} = Games.transition(riddle.id, :completed)

      # Verify 600-second delay
      expected_time = DateTime.add(DateTime.utc_now(), 600)
      assert DateTime.diff(archive_job(riddle.id).scheduled_at, expected_time, :second) < 5
    end

    test "zero cooldown archives immediately" do
      riddle = scheduled_riddle_fixture(%{archive_after_seconds: 0})

      {:ok, riddle} = Games.transition(riddle.id, :ready)
      {:ok, riddle} = Games.transition(riddle.id, :live)
      {:ok, _} = Games.transition(riddle.id, :completed)

      # Job should be available immediately (scheduled_at <= now)
      assert DateTime.compare(archive_job(riddle.id).scheduled_at, DateTime.utc_now()) in [
               :lt,
               :eq
             ]
    end

    test "default cooldown is 180 seconds" do
      riddle = scheduled_riddle_fixture()
      assert riddle.archive_after_seconds == 180

      {:ok, riddle} = Games.transition(riddle.id, :ready)
      {:ok, riddle} = Games.transition(riddle.id, :live)
      {:ok, _} = Games.transition(riddle.id, :completed)

      # Verify 3-minute delay (180 seconds)
      expected_time = DateTime.add(DateTime.utc_now(), 180)
      assert DateTime.diff(archive_job(riddle.id).scheduled_at, expected_time, :second) < 5
    end

    test "republishing after draft rollback works correctly" do
      riddle = scheduled_riddle_fixture(%{live_date: future(3600)})
      assert length(ordered_pending_jobs(riddle.id)) == 2

      # Roll back to draft: jobs are cancelled and the riddle reopens for scheduling
      {:ok, riddle} = Games.save_riddle(riddle, %{"publish_status" => "draft"})
      assert riddle.publish_status == "draft"
      assert riddle.play_status == "closed"
      assert ordered_pending_jobs(riddle.id) == []

      # Republish with a new live_date
      new_live_date = future(5400)

      {:ok, riddle} =
        Games.save_riddle(riddle, %{
          "publish_status" => "published",
          "live_date" => new_live_date
        })

      assert riddle.play_status == "scheduled"
      assert [_ready_job, live_job] = ordered_pending_jobs(riddle.id)
      assert DateTime.compare(live_job.scheduled_at, new_live_date) == :eq
    end
  end

  defp future(seconds),
    do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)

  defp ordered_pending_jobs(riddle_id) do
    Oban.Job
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
    |> where([j], j.state in ["scheduled", "available"])
    |> order_by([j], asc: j.scheduled_at)
    |> Repo.all()
  end

  defp archive_job(riddle_id) do
    Oban.Job
    |> where([j], j.worker == "Riddlr.Workers.ArchiveRiddleTransitionWorker")
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
    |> Repo.one()
  end
end
