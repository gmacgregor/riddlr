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

    test "delete_riddle/1 cancels the riddle's pending jobs" do
      riddle = scheduled_riddle_fixture()

      assert {:ok, %Riddle{}} = Games.delete_riddle(riddle)

      pending =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["available", "scheduled", "retryable"])
        |> Riddlr.Repo.all()

      assert pending == []
    end

    test "delete_riddle/1 announces :riddle_deleted to the admin topic" do
      riddle = riddle_fixture()
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:changed")

      assert {:ok, %Riddle{}} = Games.delete_riddle(riddle)

      assert_receive {:riddle_deleted, %{id: ^riddle_id}}
    end

    test "delete_riddle/1 announces :riddle_unscheduled for a scheduled riddle" do
      riddle = scheduled_riddle_fixture()
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:scheduled")

      assert {:ok, %Riddle{}} = Games.delete_riddle(riddle)

      assert_receive {:riddle_unscheduled, %{id: ^riddle_id}}
    end

    test "change_riddle/1 returns a riddle changeset" do
      riddle = riddle_fixture()
      assert %Ecto.Changeset{} = Games.change_riddle(riddle)
    end
  end

  describe "riddle state machine" do
    import Riddlr.GamesFixtures

    test "full riddle lifecycle from closed to archived" do
      live_date = DateTime.add(DateTime.utc_now(), 600, :second) |> DateTime.truncate(:second)

      # Schedule
      riddle = scheduled_riddle_fixture(%{live_date: live_date})
      assert riddle.play_status == "scheduled"
      assert DateTime.compare(riddle.live_date, live_date) == :eq

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

    test "invalid state transitions return errors" do
      riddle = riddle_fixture(%{play_status: "closed", publish_status: "published"})

      # Cannot go directly from closed to live
      assert {:invalid, "closed", :live} = Games.transition(riddle.id, :live)

      # Cannot go from closed to completed
      assert {:invalid, "closed", :completed} = Games.transition(riddle.id, :completed)
    end

    test "idempotency: transitioning to ready twice on a scheduled riddle" do
      riddle = scheduled_riddle_fixture()

      # First call succeeds
      {:ok, updated_riddle} = Games.transition(riddle.id, :ready)
      assert updated_riddle.play_status == "ready"

      # Second call is rejected as an invalid transition
      assert {:invalid, "ready", :ready} = Games.transition(riddle.id, :ready)
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

  describe "next_riddle/0" do
    import Riddlr.GamesFixtures

    test "returns nil when no riddle is upcoming or live" do
      assert Games.next_riddle() == nil
    end

    test "returns the upcoming published riddle with the soonest Live date" do
      later = put_state(riddle_fixture(), "scheduled", "published", 7200)
      sooner = put_state(riddle_fixture(), "ready", "published", 600)

      next = Games.next_riddle()

      assert next.id == sooner.id
      assert next.category.name == "logic"
      refute next.id == later.id
    end

    test "puts a live riddle before an upcoming one" do
      put_state(riddle_fixture(), "scheduled", "published", 600)
      live = put_state(riddle_fixture(), "live", "published", -30)

      assert Games.next_riddle().id == live.id
    end

    test "ignores drafts and riddles that are closed or finished" do
      put_state(riddle_fixture(), "scheduled", "draft", 60)
      put_state(riddle_fixture(), "closed", "published", 60)
      put_state(riddle_fixture(), "completed", "published", -60)
      put_state(riddle_fixture(), "archived", "published", -120)

      assert Games.next_riddle() == nil
    end
  end

  describe "list_upcoming_riddles/1" do
    import Riddlr.GamesFixtures

    test "returns upcoming published riddles after the next one, soonest first" do
      put_state(riddle_fixture(), "ready", "published", 60)
      third = put_state(riddle_fixture(), "scheduled", "published", 7200)
      second = put_state(riddle_fixture(), "scheduled", "published", 600)
      put_state(riddle_fixture(), "scheduled", "draft", 300)
      put_state(riddle_fixture(), "completed", "published", -60)

      upcoming = Games.list_upcoming_riddles(3)

      assert Enum.map(upcoming, & &1.id) == [second.id, third.id]
      assert hd(upcoming).category.name == "logic"
    end

    test "keeps every upcoming riddle when the next one is live" do
      put_state(riddle_fixture(), "live", "published", -30)
      upcoming = put_state(riddle_fixture(), "scheduled", "published", 600)

      assert Enum.map(Games.list_upcoming_riddles(3), & &1.id) == [upcoming.id]
    end

    test "returns at most `limit` riddles" do
      for secs <- [60, 120, 180, 240],
          do: put_state(riddle_fixture(), "scheduled", "published", secs)

      assert length(Games.list_upcoming_riddles(2)) == 2
    end
  end

  describe "last_finished_riddle/0" do
    import Riddlr.GamesFixtures

    test "returns nil when no riddle has finished" do
      put_state(riddle_fixture(), "live", "published", -30)

      assert Games.last_finished_riddle() == nil
    end

    test "returns the finished riddle with the latest Live date" do
      put_state(riddle_fixture(), "archived", "published", -7200)
      last = put_state(riddle_fixture(), "completed", "published", -600)
      put_state(riddle_fixture(), "live", "published", -30)

      found = Games.last_finished_riddle()

      assert found.id == last.id
      assert found.category.name == "logic"
    end

    test "counts archived riddles" do
      archived = put_state(riddle_fixture(), "archived", "published", -60)
      put_state(riddle_fixture(), "completed", "published", -600)

      assert Games.last_finished_riddle().id == archived.id
    end
  end

  # Sets Play status, Publish status and a Live date `secs` from now, skipping
  # the changeset's transition checks.
  defp put_state(riddle, play_status, publish_status, secs) do
    live_date = DateTime.utc_now() |> DateTime.add(secs, :second) |> DateTime.truncate(:second)

    riddle
    |> Ecto.Changeset.change(
      play_status: play_status,
      publish_status: publish_status,
      live_date: live_date
    )
    |> Riddlr.Repo.update!()
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
  end
end
