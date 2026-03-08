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
      assert Games.list_riddles() == [riddle]
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
               DateTime.add(live_date, -300, :second)
             ) == :eq

      assert DateTime.compare(result.live_job.scheduled_at, live_date) == :eq

      # Ready
      {:ok, riddle} = Games.ready_riddle(riddle.id)
      assert riddle.play_status == "ready"

      # Live
      {:ok, riddle} = Games.start_riddle(riddle.id)
      assert riddle.play_status == "live"

      # Complete
      {:ok, riddle} = Games.complete_riddle(riddle.id)
      assert riddle.play_status == "completed"

      # Archive
      {:ok, riddle} = Games.archive_riddle(riddle.id)
      assert riddle.play_status == "archived"
    end

    test "schedule_riddle enqueues two jobs with correct timing" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "published"})
      live_date = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, result} = Games.schedule_riddle(riddle, live_date)

      # Verify ready job scheduled 5 min before live
      assert result.ready_job.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker"
      assert result.ready_job.args == %{"riddle_id" => riddle.id}
      assert DateTime.diff(result.ready_job.scheduled_at, live_date, :second) == -300

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
      riddle = riddle_fixture(%{play_status: "closed"})

      # Cannot go directly from closed to live
      {:error, error} = Games.start_riddle(riddle.id)
      assert error == "cannot transition from closed to live"

      # Cannot go from closed to completed
      {:error, error} = Games.complete_riddle(riddle.id)
      assert error == "cannot transition from closed to completed"
    end

    test "idempotency: calling ready_riddle twice on scheduled riddle" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "published"})
      live_date = DateTime.add(DateTime.utc_now(), 600, :second)

      {:ok, result} = Games.schedule_riddle(riddle, live_date)
      riddle_id = result.riddle.id

      # First call succeeds
      {:ok, updated_riddle} = Games.ready_riddle(riddle_id)
      assert updated_riddle.play_status == "ready"

      # Second call fails with error
      {:error, error} = Games.ready_riddle(riddle_id)
      assert error == "cannot transition from ready to ready"
    end

    test "complete_riddle succeeds when riddle has a winner" do
      riddle = riddle_fixture(%{play_status: "live"})
      user = Riddlr.AccountsFixtures.user_fixture()
      {:ok, _} = Games.record_first_solver(riddle.id, user.id)

      {:ok, completed} = Games.complete_riddle(riddle.id)
      assert completed.play_status == "completed"
      assert completed.first_solver_id == user.id
    end

    test "complete_riddle records no winner when first_solver_id is nil" do
      riddle = riddle_fixture(%{play_status: "live"})

      {:ok, completed} = Games.complete_riddle(riddle.id)
      assert completed.play_status == "completed"
      assert is_nil(completed.first_solver_id)
    end

    test "complete_riddle enqueues archive job with 180 second delay" do
      riddle = riddle_fixture(%{play_status: "live"})

      {:ok, updated_riddle} = Games.complete_riddle(riddle.id)

      assert updated_riddle.play_status == "completed"

      # Verify archive job was enqueued
      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )
    end

    test "complete_riddle uses custom archive_cooldown_minutes" do
      riddle = riddle_fixture(%{play_status: "live", archive_cooldown_minutes: 5})

      {:ok, updated_riddle} = Games.complete_riddle(riddle.id)

      assert updated_riddle.play_status == "completed"

      # Verify archive job was enqueued with custom delay (5 minutes = 300 seconds)
      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )

      # Verify the job is scheduled in the future (approximately 5 minutes)
      [job] = all_enqueued(worker: Riddlr.Workers.ArchiveRiddleTransitionWorker)
      scheduled_at = job.scheduled_at
      now = DateTime.utc_now()

      # Should be scheduled approximately 5 minutes in the future (allowing 5 second tolerance)
      scheduled_diff = DateTime.diff(scheduled_at, now)
      assert scheduled_diff >= 295 and scheduled_diff <= 305
    end

    test "complete_riddle supports zero cooldown for immediate archiving" do
      riddle = riddle_fixture(%{play_status: "live", archive_cooldown_minutes: 0})

      {:ok, updated_riddle} = Games.complete_riddle(riddle.id)

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

    test "PubSub events broadcast on state transitions" do
      riddle = riddle_fixture(%{play_status: "scheduled"})

      # Subscribe to PubSub topic
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:ready")

      {:ok, updated_riddle} = Games.ready_riddle(riddle.id)

      # Assert broadcast received (category is preloaded in broadcast)
      assert_receive {:riddle_ready, broadcast_riddle}
      assert broadcast_riddle.id == updated_riddle.id
      assert broadcast_riddle.play_status == "ready"
      assert broadcast_riddle.category.id == riddle.category_id
    end
  end

  describe "start_riddle/1 scheduling" do
    import Riddlr.GamesFixtures

    test "enqueues CompleteRiddleWorker when live_until_solved is false" do
      riddle = riddle_fixture(%{play_status: "ready", publish_status: "published"})

      {:ok, _riddle} = Games.start_riddle(riddle.id)

      assert_enqueued(
        worker: Riddlr.Workers.CompleteRiddleWorker,
        args: %{"riddle_id" => riddle.id}
      )
    end

    test "does not enqueue CompleteRiddleWorker when live_until_solved is true" do
      riddle =
        riddle_fixture(%{
          play_status: "ready",
          publish_status: "published",
          live_until_solved: true
        })

      {:ok, _riddle} = Games.start_riddle(riddle.id)

      refute_enqueued(
        worker: Riddlr.Workers.CompleteRiddleWorker,
        args: %{"riddle_id" => riddle.id}
      )
    end

    test "CompleteRiddleWorker scheduled after solve_time seconds" do
      riddle =
        riddle_fixture(%{play_status: "ready", publish_status: "published", solve_time: 120})

      {:ok, _riddle} = Games.start_riddle(riddle.id)

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

  describe "archive_cooldown_minutes" do
    import Riddlr.GamesFixtures

    test "defaults to 3 minutes" do
      riddle = riddle_fixture()
      assert riddle.archive_cooldown_minutes == 3
    end

    test "accepts valid cooldown values" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        archive_cooldown_minutes: 5
      }

      assert {:ok, riddle} = Games.create_riddle(attrs)
      assert riddle.archive_cooldown_minutes == 5
    end

    test "rejects negative cooldown values" do
      category = get_test_category()

      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        category_id: category.id,
        archive_cooldown_minutes: -1
      }

      assert {:error, changeset} = Games.create_riddle(attrs)

      assert %{archive_cooldown_minutes: ["must be greater than or equal to 0"]} =
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
        archive_cooldown_minutes: 0
      }

      assert {:ok, riddle} = Games.create_riddle(attrs)
      assert riddle.archive_cooldown_minutes == 0
    end
  end
end
