defmodule Riddlr.GamesTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  alias Riddlr.Games

  describe "riddles" do
    alias Riddlr.Games.Riddle

    import Riddlr.GamesFixtures

    @invalid_attrs %{name: nil, description: nil, answers: [], solve_time: nil, category_id: nil}

    test "list_riddles/0 returns all riddles" do
      riddle = riddle_fixture()
      riddles = Games.list_riddles()
      assert Enum.any?(riddles, &(&1.id == riddle.id))
    end

    test "get_riddle!/1 returns the riddle with given id" do
      riddle = riddle_fixture()
      assert Games.get_riddle!(riddle.id) == riddle
    end

    test "create_riddle/1 with valid data creates a riddle" do
      # Get or create logic category for test
      category =
        Riddlr.Repo.get_by(Riddlr.Games.Category, name: "logic") ||
          Riddlr.Repo.insert!(%Riddlr.Games.Category{name: "logic"})

      valid_attrs = %{
        name: "Test Riddle",
        description: "A test riddle description",
        answers: ["answer1", "answer2"],
        solve_time: 60,
        category_id: category.id,
        difficulty: "medium"
      }

      assert {:ok, %Riddle{} = riddle} = Games.create_riddle(valid_attrs)
      assert riddle.name == "Test Riddle"
      assert riddle.description == "A test riddle description"
      assert riddle.answers == ["answer1", "answer2"]
      assert riddle.solve_time == 60
      assert riddle.play_status == "closed"
      assert riddle.publish_status == "draft"
    end

    test "create_riddle/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Games.create_riddle(@invalid_attrs)
    end

    test "create_riddle/1 requires at least one answer" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: [],
        solve_time: 60,
        category_id: category.id
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{answers: ["must have at least one answer"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates play_status enum" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        play_status: "invalid_status"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{play_status: ["is invalid"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates difficulty enum" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        difficulty: "impossible"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{difficulty: ["is invalid"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates publish_status enum" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        publish_status: "invalid_status"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{publish_status: ["is invalid"]} = errors_on(changeset)
    end

    test "create_riddle/1 rejects empty strings in answers array" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["valid answer", "", "  "],
        solve_time: 60,
        category_id: category.id
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{answers: ["all answers must be non-empty strings"]} = errors_on(changeset)
    end

    defp get_test_category do
      Riddlr.Repo.get_by(Riddlr.Games.Category, name: "logic") ||
        Riddlr.Repo.insert!(%Riddlr.Games.Category{name: "logic"})
    end

    test "update_riddle/2 with valid data updates the riddle" do
      riddle = riddle_fixture()

      update_attrs = %{
        name: "Updated Name",
        description: "Updated description",
        answers: ["new_answer"],
        solve_time: 120
      }

      assert {:ok, %Riddle{} = riddle} = Games.update_riddle(riddle, update_attrs)
      assert riddle.name == "Updated Name"
      assert riddle.description == "Updated description"
      assert riddle.answers == ["new_answer"]
      assert riddle.solve_time == 120
    end

    test "update_riddle/2 with invalid data returns error changeset" do
      riddle = riddle_fixture()
      assert {:error, %Ecto.Changeset{}} = Games.update_riddle(riddle, @invalid_attrs)
      assert riddle == Games.get_riddle!(riddle.id)
    end

    test "delete_riddle/1 deletes the riddle" do
      riddle = riddle_fixture()
      assert {:ok, %Riddle{}} = Games.delete_riddle(riddle)
      assert_raise Ecto.NoResultsError, fn -> Games.get_riddle!(riddle.id) end
    end

    test "delete_riddle/1 clears the riddle's ETS rows" do
      riddle = riddle_fixture()
      user_id = :erlang.unique_integer([:positive])

      :ets.insert(
        :riddle_answers,
        {{riddle.id, user_id}, "answer", System.monotonic_time(:microsecond), true, nil}
      )

      :ets.insert(:answer_cooldowns, {{riddle.id, user_id}, System.monotonic_time(:microsecond)})

      assert {:ok, %Riddle{}} = Games.delete_riddle(riddle)

      assert :ets.lookup(:riddle_answers, {riddle.id, user_id}) == []
      assert :ets.lookup(:answer_cooldowns, {riddle.id, user_id}) == []
    end

    test "change_riddle/1 returns a riddle changeset" do
      riddle = riddle_fixture()
      assert %Ecto.Changeset{} = Games.change_riddle(riddle)
    end
  end

  describe "riddle state machine" do
    import Riddlr.GamesFixtures

    test "full riddle lifecycle from closed to archived" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "published"})
      live_date = DateTime.add(DateTime.utc_now(), 600, :second) |> DateTime.truncate(:second)

      # Schedule
      {:ok, result} = Games.schedule_riddle(riddle, live_date)
      assert result.riddle.play_status == "scheduled"
      assert DateTime.compare(result.riddle.live_date, live_date) == :eq

      assert DateTime.compare(
               result.ready_job.scheduled_at,
               DateTime.add(live_date, -result.riddle.ready_before_seconds, :second)
             ) == :eq

      assert DateTime.compare(result.live_job.scheduled_at, live_date) == :eq

      # Ready
      {:ok, riddle} = Games.transition(riddle.id, :ready)
      assert riddle.play_status == "ready"

      # Live
      {:ok, riddle} = Games.transition(riddle.id, :live)
      assert riddle.play_status == "live"

      # Complete
      {:ok, riddle} = Games.transition(riddle.id, :completed)
      assert riddle.play_status == "completed"

      # Archive
      {:ok, riddle} = Games.transition(riddle.id, :archived)
      assert riddle.play_status == "archived"
    end

    test "schedule_riddle enqueues two jobs with correct timing" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "published"})
      live_date = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, result} = Games.schedule_riddle(riddle, live_date)

      # Verify ready job scheduled ready_before_seconds before live
      assert result.ready_job.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker"
      assert result.ready_job.args == %{"riddle_id" => riddle.id}
      expected_lead_seconds = -result.riddle.ready_before_seconds

      assert DateTime.diff(result.ready_job.scheduled_at, live_date, :second) ==
               expected_lead_seconds

      # Verify live job scheduled at live_date
      assert result.live_job.worker == "Riddlr.Workers.LiveRiddleTransitionWorker"
      assert result.live_job.args == %{"riddle_id" => riddle.id}
      assert DateTime.compare(result.live_job.scheduled_at, live_date) == :eq
    end

    test "schedule_riddle returns error when riddle is not published" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "draft"})
      live_date = DateTime.add(DateTime.utc_now(), 600, :second)

      assert {:error, :riddle_not_published} = Games.schedule_riddle(riddle, live_date)
    end

    test "invalid state transitions return errors" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "published"})

      # Cannot go directly from closed to live
      assert {:invalid, "closed", :live} = Games.transition(riddle.id, :live)

      # Cannot go from closed to completed
      assert {:invalid, "closed", :completed} = Games.transition(riddle.id, :completed)
    end

    test "idempotency: transitioning to ready twice on a scheduled riddle" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "published"})
      live_date = DateTime.add(DateTime.utc_now(), 600, :second)

      {:ok, result} = Games.schedule_riddle(riddle, live_date)
      riddle_id = result.riddle.id

      # First call succeeds
      {:ok, updated_riddle} = Games.transition(riddle_id, :ready)
      assert updated_riddle.play_status == "ready"

      # Second call is rejected as an invalid transition
      assert {:invalid, "ready", :ready} = Games.transition(riddle_id, :ready)
    end

    test "completing succeeds when riddle has a winner" do
      riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})
      user = Riddlr.AccountsFixtures.user_fixture()
      {:ok, _} = Games.record_first_solver(riddle.id, user.id)

      {:ok, completed} = Games.transition(riddle.id, :completed)
      assert completed.play_status == "completed"
      assert completed.first_solver_id == user.id
    end

    test "completing records no winner when first_solver_id is nil" do
      riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

      {:ok, completed} = Games.transition(riddle.id, :completed)
      assert completed.play_status == "completed"
      assert is_nil(completed.first_solver_id)
    end

    test "completing enqueues archive job with the default 180 second delay" do
      riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

      {:ok, updated_riddle} = Games.transition(riddle.id, :completed)

      assert updated_riddle.play_status == "completed"

      # Verify archive job was enqueued
      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )
    end

    test "completing uses custom archive_after_seconds" do
      riddle =
        riddle_fixture(%{
          play_status: "live",
          publish_status: "published",
          archive_after_seconds: 300
        })

      {:ok, updated_riddle} = Games.transition(riddle.id, :completed)

      assert updated_riddle.play_status == "completed"

      # Verify archive job was enqueued with custom delay (300 seconds)
      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )

      # Verify the job is scheduled in the future (approximately 300 seconds)
      [job] = all_enqueued(worker: Riddlr.Workers.ArchiveRiddleTransitionWorker)
      scheduled_at = job.scheduled_at
      now = DateTime.utc_now()

      # Should be scheduled approximately 300 seconds in the future (allowing 5 second tolerance)
      scheduled_diff = DateTime.diff(scheduled_at, now)
      assert scheduled_diff >= 295 and scheduled_diff <= 305
    end

    test "completing supports zero cooldown for immediate archiving" do
      riddle =
        riddle_fixture(%{
          play_status: "live",
          publish_status: "published",
          archive_after_seconds: 0
        })

      {:ok, updated_riddle} = Games.transition(riddle.id, :completed)

      assert updated_riddle.play_status == "completed"

      # Verify archive job was enqueued immediately
      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )

      # Verify the job is scheduled for immediate execution (within 5 seconds)
      [job] = all_enqueued(worker: Riddlr.Workers.ArchiveRiddleTransitionWorker)
      scheduled_at = job.scheduled_at
      now = DateTime.utc_now()

      scheduled_diff = DateTime.diff(scheduled_at, now)
      assert scheduled_diff >= -5 and scheduled_diff <= 5
    end

    test "state validation prevents invalid changeset transitions" do
      riddle = riddle_fixture(%{play_status: "closed"})
      # Reload to get the actual struct with current state
      riddle = Riddlr.Repo.get!(Riddlr.Games.Riddle, riddle.id)

      # Try to update directly to live (bypassing Games functions)
      changeset = Riddlr.Games.Riddle.changeset(riddle, %{play_status: "live"})
      refute changeset.valid?
      assert %{play_status: ["cannot transition from closed to live"]} = errors_on(changeset)
    end
  end

  describe "transition/3 complete job scheduling" do
    import Riddlr.GamesFixtures

    test "CompleteRiddleWorker scheduled after solve_time seconds" do
      riddle =
        riddle_fixture(%{play_status: "ready", publish_status: "published", solve_time: 120})

      {:ok, _riddle} = Games.transition(riddle.id, :live)

      [job] = all_enqueued(worker: Riddlr.Workers.CompleteRiddleWorker)
      diff = DateTime.diff(job.scheduled_at, DateTime.utc_now())
      assert diff >= 115 and diff <= 125
    end
  end

  describe "update_riddle/2 with draft rollback" do
    import Riddlr.GamesFixtures

    test "cancels all pending workers when changing to draft status" do
      riddle =
        riddle_fixture(%{
          publish_status: "published",
          play_status: "closed"
        })

      # Schedule jobs
      live_date = DateTime.add(DateTime.utc_now(), 3600, :second)
      {:ok, result} = Games.schedule_riddle(riddle, live_date)
      riddle_id = result.riddle.id

      # Verify jobs exist
      pending_before =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(pending_before) == 2

      # Move back to draft
      riddle = Games.get_riddle!(riddle_id)
      {:ok, updated} = Games.update_riddle(riddle, %{publish_status: "draft"})

      assert updated.publish_status == "draft"
      assert updated.play_status == "closed"

      # Verify jobs cancelled
      pending_after =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(pending_after) == 0
    end

    test "does not cancel jobs when changing other fields" do
      riddle =
        riddle_fixture(%{
          publish_status: "published",
          play_status: "closed"
        })

      # Schedule jobs
      live_date = DateTime.add(DateTime.utc_now(), 3600, :second)
      {:ok, result} = Games.schedule_riddle(riddle, live_date)
      riddle_id = result.riddle.id

      # Update other fields without changing publish_status
      riddle = Games.get_riddle!(riddle_id)
      {:ok, _updated} = Games.update_riddle(riddle, %{name: "Updated Name"})

      # Verify jobs still exist
      pending_after =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(pending_after) == 2
    end

    test "does not cancel jobs when keeping published status" do
      riddle =
        riddle_fixture(%{
          publish_status: "published",
          play_status: "closed"
        })

      # Schedule jobs
      live_date = DateTime.add(DateTime.utc_now(), 3600, :second)
      {:ok, result} = Games.schedule_riddle(riddle, live_date)
      riddle_id = result.riddle.id

      # Update while keeping published status
      riddle = Games.get_riddle!(riddle_id)

      {:ok, _updated} =
        Games.update_riddle(riddle, %{publish_status: "published", name: "Still Published"})

      # Verify jobs still exist
      pending_after =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(pending_after) == 2
    end
  end

  describe "record_first_solver/2" do
    import Riddlr.GamesFixtures
    import Riddlr.AccountsFixtures

    test "records first solver when field is nil" do
      riddle = riddle_fixture(%{play_status: "live"})
      user = user_fixture()

      assert {:ok, :recorded} = Games.record_first_solver(riddle.id, user.id)
      assert Games.get_riddle!(riddle.id).first_solver_id == user.id
    end

    test "no-op when first solver already set" do
      riddle = riddle_fixture(%{play_status: "live"})
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, :recorded} = Games.record_first_solver(riddle.id, user1.id)
      assert {:ok, :already_set} = Games.record_first_solver(riddle.id, user2.id)
      assert Games.get_riddle!(riddle.id).first_solver_id == user1.id
    end
  end

  describe "archive_after_seconds" do
    import Riddlr.GamesFixtures

    test "defaults to 180 seconds" do
      riddle = riddle_fixture()
      assert riddle.archive_after_seconds == 180
    end

    test "accepts valid cooldown values" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        archive_after_seconds: 300
      }

      assert {:ok, riddle} = Games.create_riddle(attrs)
      assert riddle.archive_after_seconds == 300
    end

    test "rejects negative cooldown values" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        archive_after_seconds: -1
      }

      assert {:error, changeset} = Games.create_riddle(attrs)

      assert %{archive_after_seconds: ["must be greater than or equal to 0"]} =
               errors_on(changeset)
    end

    test "allows zero to skip cooldown" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        archive_after_seconds: 0
      }

      assert {:ok, riddle} = Games.create_riddle(attrs)
      assert riddle.archive_after_seconds == 0
    end
  end

  describe "ready_before_seconds" do
    import Riddlr.GamesFixtures

    test "defaults to 600 seconds" do
      riddle = riddle_fixture()
      assert riddle.ready_before_seconds == 600
    end

    test "is saved and persists via changeset" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        ready_before_seconds: 15
      }

      assert {:ok, riddle} = Games.create_riddle(attrs)
      assert riddle.ready_before_seconds == 15
    end

    test "rejects zero or negative values" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        ready_before_seconds: 0
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{ready_before_seconds: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "schedule_riddle uses per-riddle ready_before_seconds" do
      riddle =
        riddle_fixture(%{
          play_status: "closed",
          publish_status: "published",
          ready_before_seconds: 20
        })

      live_date = DateTime.add(DateTime.utc_now(), 7200, :second)
      {:ok, result} = Games.schedule_riddle(riddle, live_date)

      expected_offset = -riddle.ready_before_seconds
      assert DateTime.diff(result.ready_job.scheduled_at, live_date, :second) == expected_offset
    end
  end

  describe "cancel_complete_worker/1" do
    import Riddlr.GamesFixtures

    test "cancels a scheduled CompleteRiddleWorker for a riddle" do
      riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

      # Enqueue a job
      {:ok, _job} =
        Riddlr.Workers.CompleteRiddleWorker.new(%{"riddle_id" => riddle.id})
        |> Oban.insert()

      assert_enqueued(
        worker: Riddlr.Workers.CompleteRiddleWorker,
        args: %{"riddle_id" => riddle.id}
      )

      {:ok, count} = Games.cancel_complete_worker(riddle.id)
      assert count == 1

      refute_enqueued(
        worker: Riddlr.Workers.CompleteRiddleWorker,
        args: %{"riddle_id" => riddle.id}
      )
    end

    test "returns {:ok, 0} when no jobs exist" do
      riddle = riddle_fixture(%{play_status: "live"})
      assert {:ok, 0} = Games.cancel_complete_worker(riddle.id)
    end

    test "does not cancel ArchiveRiddleTransitionWorker jobs" do
      riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

      {:ok, _job} =
        Riddlr.Workers.ArchiveRiddleTransitionWorker.new(%{"riddle_id" => riddle.id})
        |> Oban.insert()

      Games.cancel_complete_worker(riddle.id)

      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{"riddle_id" => riddle.id}
      )
    end
  end
end
