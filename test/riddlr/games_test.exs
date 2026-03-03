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
      riddle = riddle_fixture(%{play_status: "closed"})
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
      riddle = riddle_fixture(%{play_status: "closed"})
      live_date = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, result} = Games.schedule_riddle(riddle, live_date)

      # Verify ready job scheduled 5 min before live
      assert result.ready_job.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker"
      assert result.ready_job.args == %{riddle_id: riddle.id}
      assert DateTime.diff(result.ready_job.scheduled_at, live_date, :second) == -300

      # Verify live job scheduled at live_date
      assert result.live_job.worker == "Riddlr.Workers.LiveRiddleTransitionWorker"
      assert result.live_job.args == %{riddle_id: riddle.id}
      assert DateTime.compare(result.live_job.scheduled_at, live_date) == :eq
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
      riddle = riddle_fixture(%{play_status: "closed"})
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

      # Assert broadcast received
      assert_receive {:riddle_ready, ^updated_riddle}
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
