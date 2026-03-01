defmodule Riddlr.Workers.ReadyRiddleTransitionWorkerTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Ecto.Query
  import Riddlr.GamesFixtures

  alias Riddlr.Workers.ReadyRiddleTransitionWorker

  test "transitions scheduled riddle to ready" do
    riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "published"})

    assert :ok = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "ready"
  end

  test "cancels if riddle is not published" do
    riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "draft"})

    assert {:cancel, message} = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "not published"
    assert message =~ "draft"
  end

  test "idempotency - cancels if already ready" do
    riddle = riddle_fixture(%{play_status: "ready", publish_status: "published"})

    assert {:cancel, message} = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "Already transitioned"
    assert message =~ "ready"
  end

  test "cancels if riddle is in wrong state (live)" do
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    assert {:cancel, message} = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert message =~ "Already transitioned"
    assert message =~ "live"
  end

  test "unique constraint prevents duplicate jobs within 1 hour" do
    riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "published"})

    # Insert first job
    assert {:ok, _job1} =
             ReadyRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()

    # Try to insert duplicate job - should be discarded due to unique constraint
    assert {:ok, _job2} =
             ReadyRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()

    # Verify only one job exists in queue
    job_count =
      Riddlr.Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker",
          where: fragment("args->>'riddle_id' = ?", ^to_string(riddle.id))
        ),
        :count
      )

    assert job_count == 1
  end
end
