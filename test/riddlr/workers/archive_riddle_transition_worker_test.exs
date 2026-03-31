defmodule Riddlr.Workers.ArchiveRiddleTransitionWorkerTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Ecto.Query
  import Riddlr.GamesFixtures

  alias Riddlr.Workers.ArchiveRiddleTransitionWorker

  test "transitions completed riddle to archived" do
    riddle = riddle_fixture(%{play_status: "completed", publish_status: "published"})

    assert :ok = perform_job(ArchiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert Riddlr.Repo.reload(riddle).play_status == "archived"
  end

  test "cancels if riddle is not published" do
    riddle = riddle_fixture(%{play_status: "completed", publish_status: "draft"})

    assert {:cancel, message} =
             perform_job(ArchiveRiddleTransitionWorker, %{riddle_id: riddle.id})

    assert message =~ "not published"
    assert message =~ "draft"
  end

  test "idempotency - cancels if already archived" do
    riddle = riddle_fixture(%{play_status: "archived", publish_status: "published"})

    assert {:cancel, message} =
             perform_job(ArchiveRiddleTransitionWorker, %{riddle_id: riddle.id})

    assert message =~ "Already transitioned"
    assert message =~ "archived"
  end

  test "cancels if riddle is in wrong state (live)" do
    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

    assert {:cancel, message} =
             perform_job(ArchiveRiddleTransitionWorker, %{riddle_id: riddle.id})

    assert message =~ "Already transitioned"
    assert message =~ "live"
  end

  test "unique constraint prevents duplicate jobs within 1 hour" do
    riddle = riddle_fixture(%{play_status: "completed", publish_status: "published"})

    # Insert first job
    assert {:ok, _job1} =
             ArchiveRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()

    # Try to insert duplicate - Oban handles uniqueness internally
    assert {:ok, _job2} =
             ArchiveRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()

    # Verify only one job exists in queue
    job_count =
      Riddlr.Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == "Riddlr.Workers.ArchiveRiddleTransitionWorker",
          where: fragment("args->>'riddle_id' = ?", ^to_string(riddle.id))
        ),
        :count
      )

    assert job_count == 1
  end

  describe "ETS cleanup on archive" do
    test "removes riddle answers and cooldowns from ETS after archiving" do
      riddle = riddle_fixture(%{play_status: "completed", publish_status: "published"})

      user_id = :erlang.unique_integer([:positive])

      # Manually insert ETS entries for this riddle
      :ets.insert(
        :riddle_answers,
        {{riddle.id, user_id}, "answer", System.monotonic_time(:microsecond), true, nil}
      )

      :ets.insert(:answer_cooldowns, {{riddle.id, user_id}, System.monotonic_time(:microsecond)})

      assert :ok = perform_job(ArchiveRiddleTransitionWorker, %{riddle_id: riddle.id})

      # Verify ETS entries were cleaned up
      assert :ets.lookup(:riddle_answers, {riddle.id, user_id}) == []
      assert :ets.lookup(:answer_cooldowns, {riddle.id, user_id}) == []
    end
  end

  describe "custom archive cooldown" do
    test "respects riddle's archive_after_seconds setting" do
      riddle =
        riddle_fixture(%{
          play_status: "completed",
          publish_status: "published",
          archive_after_seconds: 5
        })

      assert :ok = perform_job(ArchiveRiddleTransitionWorker, %{riddle_id: riddle.id})

      updated = Riddlr.Repo.reload(riddle)
      assert updated.play_status == "archived"
    end

    test "works with zero cooldown for immediate archiving" do
      riddle =
        riddle_fixture(%{
          play_status: "completed",
          publish_status: "published",
          archive_after_seconds: 0
        })

      assert :ok = perform_job(ArchiveRiddleTransitionWorker, %{riddle_id: riddle.id})

      updated = Riddlr.Repo.reload(riddle)
      assert updated.play_status == "archived"
    end
  end
end
