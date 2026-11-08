defmodule Riddlr.Workers.LiveRiddleTransitionWorkerTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Ecto.Query
  import Riddlr.GamesFixtures

  alias Riddlr.Workers.LiveRiddleTransitionWorker

  test "transitions ready riddle to live" do
    riddle = riddle_fixture(%{play_status: "ready", publish_status: "published"})

    assert :ok = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "live"
  end

  # Both jobs fall due at once after downtime and run side by side. The Live
  # job used to cancel on a riddle the Ready job had not moved yet, and the
  # Ready job then left it in `ready` for good.
  test "takes a late scheduled riddle straight to live" do
    riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "published"})

    assert :ok = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "live"
  end

  test "cancels if riddle is not published" do
    riddle = riddle_fixture(%{play_status: "ready", publish_status: "draft"})

    assert {:cancel, message} = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "not published"
    assert message =~ "draft"
  end

  test "idempotency - cancels if already live" do
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    assert {:cancel, message} = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "cannot transition"
    assert message =~ "live"
  end

  test "cancels if riddle is in wrong state (completed)" do
    riddle = riddle_fixture(%{play_status: "completed", publish_status: "published"})

    assert {:cancel, message} = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "cannot transition"
    assert message =~ "completed"
  end

  test "unique constraint prevents duplicate jobs within 1 hour" do
    riddle = riddle_fixture(%{play_status: "ready", publish_status: "published"})

    # Insert first job
    assert {:ok, _job1} = LiveRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()

    # Try to insert duplicate - Oban handles uniqueness internally
    assert {:ok, _job2} = LiveRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()

    # Verify only one job exists in queue
    job_count =
      Riddlr.Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == "Riddlr.Workers.LiveRiddleTransitionWorker",
          where: fragment("args->>'riddle_id' = ?", ^to_string(riddle.id))
        ),
        :count
      )

    assert job_count == 1
  end
end
