defmodule Riddlr.Workers.CompleteRiddleWorkerTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Ecto.Query
  import Riddlr.GamesFixtures
  import Riddlr.AccountsFixtures

  alias Riddlr.Workers.CompleteRiddleWorker

  test "transitions live unsolved riddle to completed" do
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "completed"
  end

  test "cancels if riddle not found" do
    assert {:cancel, message} = perform_job(CompleteRiddleWorker, %{riddle_id: 0})
    assert message =~ "not found"
  end

  test "cancels if publish_status is draft" do
    riddle = riddle_fixture(%{play_status: "live", publish_status: "draft"})

    assert {:cancel, message} = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
    assert message =~ "not published"
    assert message =~ "draft"
  end

  test "cancels if play_status is already completed" do
    riddle = riddle_fixture(%{play_status: "completed", publish_status: "published"})

    assert {:cancel, message} = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
    assert message =~ "Already transitioned"
    assert message =~ "completed"
  end

  test "completes riddle even when a player has already won" do
    user = user_fixture()
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    {:ok, riddle} =
      Riddlr.Games.update_riddle(riddle, %{first_solver_id: user.id, play_status: "live"})

    assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "completed"
  end

  test "cancels if live_until_solved is true at execution time" do
    riddle =
      riddle_fixture(%{
        play_status: "live",
        publish_status: "published",
        live_until_solved: true
      })

    assert {:cancel, message} = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
    assert message =~ "live_until_solved"
  end

  test "unique constraint prevents duplicate jobs within 1 hour" do
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    assert {:ok, _job1} =
             CompleteRiddleWorker.new(%{"riddle_id" => riddle.id}) |> Oban.insert()

    assert {:ok, _job2} =
             CompleteRiddleWorker.new(%{"riddle_id" => riddle.id}) |> Oban.insert()

    job_count =
      Riddlr.Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == "Riddlr.Workers.CompleteRiddleWorker",
          where: fragment("args->>'riddle_id' = ?", ^to_string(riddle.id))
        ),
        :count
      )

    assert job_count == 1
  end
end
