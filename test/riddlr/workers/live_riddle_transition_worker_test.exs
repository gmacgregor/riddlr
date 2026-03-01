defmodule Riddlr.Workers.LiveRiddleTransitionWorkerTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Ecto.Query
  import Riddlr.GamesFixtures

  alias Riddlr.Workers.LiveRiddleTransitionWorker

  test "transitions ready riddle to live" do
    riddle = riddle_fixture(%{play_status: "ready"})

    assert :ok = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "live"
  end

  test "idempotency - cancels if already live" do
    riddle = riddle_fixture(%{play_status: "live"})

    assert {:cancel, message} = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "Already transitioned"
    assert message =~ "live"
  end

  test "cancels if riddle is in wrong state (completed)" do
    riddle = riddle_fixture(%{play_status: "completed"})

    assert {:cancel, message} = perform_job(LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "Already transitioned"
    assert message =~ "completed"
  end

  test "unique constraint prevents duplicate jobs within 1 hour" do
    riddle = riddle_fixture(%{play_status: "ready"})

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
