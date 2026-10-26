defmodule Riddlr.Workers.CompleteRiddleWorkerTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Ecto.Query
  import Riddlr.GamesFixtures
  import Riddlr.AccountsFixtures

  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Workers.CompleteRiddleWorker

  test "transitions live unsolved riddle to completed" do
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "completed"
  end

  describe "solves" do
    test "saves every correct solver with placement, points and solve time" do
      riddle = live_riddle()
      [first, second, third] = for _ <- 1..3, do: user_fixture()
      loser = user_fixture()

      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, first, "keyboard")
      assert :incorrect = Gameplay.submit_answer(riddle, loser, "mouse")
      assert {:correct, 2, 9} = Gameplay.submit_answer(riddle, second, "keyboard")
      assert {:correct, 3, 8} = Gameplay.submit_answer(riddle, third, "keyboard")

      assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})

      assert [
               %Solve{placement: 1, points: 10} = s1,
               %Solve{placement: 2, points: 9} = s2,
               %Solve{placement: 3, points: 8} = s3
             ] = saved_solves(riddle.id)

      assert [s1.user_id, s2.user_id, s3.user_id] == [first.id, second.id, third.id]
      assert is_integer(s1.solve_time_ms) and s1.solve_time_ms >= 0
    end

    test "saves solvers past the top 10 with 0 points" do
      riddle = live_riddle()

      for placement <- 1..12 do
        assert {:correct, ^placement, _} =
                 Gameplay.submit_answer(riddle, user_fixture(), "keyboard")
      end

      assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})

      assert Enum.map(saved_solves(riddle.id), &{&1.placement, &1.points}) ==
               Enum.zip(1..12, [10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0])
    end

    test "running the job twice saves each solve once" do
      riddle = live_riddle()
      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, user_fixture(), "keyboard")

      assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
      assert {:cancel, _} = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})

      assert [%Solve{placement: 1}] = saved_solves(riddle.id)
    end

    test "saving solves that are already stored neither fails nor duplicates" do
      riddle = live_riddle()
      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, user_fixture(), "keyboard")
      Riddlr.Repo.insert_all(Solve, Gameplay.solve_rows(riddle.id))

      assert {:ok, _} =
               Riddlr.Games.transition(riddle.id, :completed, %{
                 solves: Gameplay.solve_rows(riddle.id)
               })

      assert [%Solve{placement: 1}] = saved_solves(riddle.id)
    end

    test "a riddle nobody solved saves no solves" do
      riddle = live_riddle()
      assert :incorrect = Gameplay.submit_answer(riddle, user_fixture(), "mouse")

      assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})

      assert saved_solves(riddle.id) == []
    end
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
    assert message =~ "cannot transition"
    assert message =~ "completed"
  end

  test "completes riddle even when a player has already won" do
    user = user_fixture()
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    {:ok, :recorded} = Riddlr.Games.record_first_solver(riddle.id, user.id)

    assert :ok = perform_job(CompleteRiddleWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "completed"
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

  # A live, published riddle that went live a minute ago, so solves carry a time.
  defp live_riddle do
    riddle_fixture(%{
      play_status: "live",
      publish_status: "published",
      live_date: DateTime.add(DateTime.utc_now(), -60, :second)
    })
  end

  defp saved_solves(riddle_id) do
    Riddlr.Repo.all(from s in Solve, where: s.riddle_id == ^riddle_id, order_by: s.placement)
  end
end
