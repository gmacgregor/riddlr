defmodule Riddlr.GamesTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Riddlr.GamesFixtures

  alias Riddlr.Games
  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Store

  describe "riddles" do
    alias Riddlr.Games.Riddle

    @invalid_attrs %{name: nil, description: nil, answers: [], solve_time: nil, category_id: nil}

    test "list_riddles/0 returns all riddles" do
      riddle = riddle_fixture()
      riddles = Games.list_riddles()
      assert Enum.any?(riddles, &(&1.id == riddle.id))
    end

    test "list_riddles/1 returns the newest `limit` riddles, newest first" do
      [first, second, third] = for _ <- 1..3, do: riddle_fixture()

      assert Games.list_riddles(2) |> Enum.map(& &1.id) == [third.id, second.id]
      refute first.id in Enum.map(Games.list_riddles(2), & &1.id)
    end

    test "get_riddle!/1 returns the riddle with given id" do
      riddle = riddle_fixture()
      assert Games.get_riddle!(riddle.id) == riddle
    end

    test "get_riddle/2 returns the riddle, or nil if it does not exist" do
      riddle = riddle_fixture()
      assert Games.get_riddle(riddle.id) == riddle
      refute Games.get_riddle(-1)
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

      assert {:ok, %Riddle{} = riddle} = Games.create_riddle(system_scope(), valid_attrs)
      assert riddle.name == "Test Riddle"
      assert riddle.description == "A test riddle description"
      assert riddle.answers == ["answer1", "answer2"]
      assert riddle.solve_time == 60
      assert riddle.play_status == "closed"
      assert riddle.publish_status == "draft"
    end

    test "create_riddle/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Games.create_riddle(system_scope(), @invalid_attrs)
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

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)
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

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)
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

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)
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

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)
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

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)
      assert %{answers: ["all answers must be non-empty strings"]} = errors_on(changeset)
    end

    defp get_test_category do
      Riddlr.Repo.get_by(Riddlr.Games.Category, name: "logic") ||
        Riddlr.Repo.insert!(%Riddlr.Games.Category{name: "logic"})
    end

    test "get_riddle!/2 loads the category and nothing else by default" do
      riddle = riddle_fixture()

      fetched = Games.get_riddle!(riddle.id)
      assert %Riddlr.Games.Category{} = fetched.category
      refute Ecto.assoc_loaded?(fetched.first_solver)

      assert Ecto.assoc_loaded?(
               Games.get_riddle!(riddle.id, preload: [:first_solver]).first_solver
             )
    end

    test "delete_riddle/1 deletes the riddle" do
      riddle = riddle_fixture()
      assert {:ok, %Riddle{}} = Games.delete_riddle(system_scope(), riddle)
      assert_raise Ecto.NoResultsError, fn -> Games.get_riddle!(riddle.id) end
    end

    test "delete_riddle/1 clears the riddle's ETS rows" do
      riddle = riddle_fixture()
      user_id = :erlang.unique_integer([:positive])

      user = %{id: user_id, username: "user#{user_id}"}
      {:ok, 1} = Store.record(Answer.new(riddle.id, user, "answer", correct: true))
      :ok = Store.claim_cooldown({riddle.id, user_id}, 1_000_000)

      assert {:ok, %Riddle{}} = Games.delete_riddle(system_scope(), riddle)

      refute Store.guessed?(riddle.id, user_id)
      assert Store.recent_answers(riddle.id) == []
      assert :ok = Store.claim_cooldown({riddle.id, user_id}, 1_000_000)
    end

    test "delete_riddle/1 cancels the riddle's pending jobs" do
      riddle = scheduled_riddle_fixture()
      {:ok, _} = Games.transition(riddle.id, :ready)

      assert {:ok, %Riddle{}} = Games.delete_riddle(system_scope(), riddle)

      pending =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["available", "scheduled", "retryable"])
        |> Riddlr.Repo.all()

      assert pending == []
    end

    test "delete_riddle/1 leaves other riddles' jobs alone" do
      riddle = scheduled_riddle_fixture()
      other = scheduled_riddle_fixture()

      assert {:ok, %Riddle{}} = Games.delete_riddle(system_scope(), riddle)

      assert [_ | _] = Riddlr.ObanMonitor.riddle_jobs(other.id)

      assert Enum.all?(
               Riddlr.ObanMonitor.riddle_jobs(other.id),
               &(&1.state in ["available", "scheduled"])
             )

      assert Enum.all?(Riddlr.ObanMonitor.riddle_jobs(riddle.id), &(&1.state == "cancelled"))
    end

    test "delete_riddle/1 announces :riddle_deleted to the admin topic" do
      riddle = riddle_fixture()
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:changed")

      assert {:ok, %Riddle{}} = Games.delete_riddle(system_scope(), riddle)

      assert_receive {:riddle_deleted, %{id: ^riddle_id}}
    end

    test "delete_riddle/1 announces :riddle_unscheduled for a scheduled riddle" do
      riddle = scheduled_riddle_fixture()
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:scheduled")

      assert {:ok, %Riddle{}} = Games.delete_riddle(system_scope(), riddle)

      assert_receive {:riddle_unscheduled, %{id: ^riddle_id}}
    end

    test "change_riddle/1 returns a riddle changeset" do
      riddle = riddle_fixture()
      assert %Ecto.Changeset{} = Games.change_riddle(riddle)
    end
  end

  describe "riddle state machine" do
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

      {{:ok, updated_riddle}, window} =
        between_clock_reads(fn -> Games.transition(riddle.id, :completed) end)

      assert updated_riddle.play_status == "completed"

      # Verify archive job was enqueued with custom delay (300 seconds)
      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )

      [job] = all_enqueued(worker: Riddlr.Workers.ArchiveRiddleTransitionWorker)
      assert_scheduled_in(job, 300, window)
    end

    test "completing supports zero cooldown for immediate archiving" do
      riddle =
        riddle_fixture(%{
          play_status: "live",
          publish_status: "published",
          archive_after_seconds: 0
        })

      {{:ok, updated_riddle}, window} =
        between_clock_reads(fn -> Games.transition(riddle.id, :completed) end)

      assert updated_riddle.play_status == "completed"

      # Verify archive job was enqueued immediately
      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )

      [job] = all_enqueued(worker: Riddlr.Workers.ArchiveRiddleTransitionWorker)
      assert_scheduled_in(job, 0, window)
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
    test "CompleteRiddleWorker scheduled after solve_time seconds" do
      riddle =
        riddle_fixture(%{play_status: "ready", publish_status: "published", solve_time: 120})

      {{:ok, _riddle}, window} = between_clock_reads(fn -> Games.transition(riddle.id, :live) end)

      [job] = all_enqueued(worker: Riddlr.Workers.CompleteRiddleWorker)
      assert_scheduled_in(job, 120, window)
    end
  end

  describe "transition/3 to ready" do
    test "queues the Lobby-open notification fan-out" do
      riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "published"})

      {:ok, _riddle} = Games.transition(riddle.id, :ready)

      assert_enqueued(
        worker: Riddlr.Workers.NotificationFanOutWorker,
        args: %{"riddle_id" => riddle.id, "lead_time" => "lobby_open"},
        queue: :notifications
      )
    end
  end

  describe "next_riddle/0" do
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
    test "returns upcoming published riddles, the next one included, soonest first" do
      first = put_state(riddle_fixture(), "ready", "published", 60)
      third = put_state(riddle_fixture(), "scheduled", "published", 7200)
      second = put_state(riddle_fixture(), "scheduled", "published", 600)
      put_state(riddle_fixture(), "scheduled", "draft", 300)
      put_state(riddle_fixture(), "completed", "published", -60)

      upcoming = Games.list_upcoming_riddles(3)

      assert Enum.map(upcoming, & &1.id) == [first.id, second.id, third.id]
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

  describe "record_first_solver/3" do
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

    test "stores the first solve time in milliseconds and keeps the first one" do
      riddle = riddle_fixture(%{play_status: "live"})

      {:ok, :recorded} = Games.record_first_solver(riddle.id, user_fixture().id, 4_567)
      {:ok, :already_set} = Games.record_first_solver(riddle.id, user_fixture().id, 4_999)

      assert Games.get_riddle!(riddle.id).first_solve_time == 4_567
    end
  end

  describe "archive_after_seconds" do
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

      assert {:ok, riddle} = Games.create_riddle(system_scope(), attrs)
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

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)

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

      assert {:ok, riddle} = Games.create_riddle(system_scope(), attrs)
      assert riddle.archive_after_seconds == 0
    end
  end

  describe "ready_before_seconds" do
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

      assert {:ok, riddle} = Games.create_riddle(system_scope(), attrs)
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

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)
      assert %{ready_before_seconds: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "practice riddles" do
    test "create_practice_riddle/1 saves a description and an answer" do
      assert {:ok, practice} =
               Games.create_practice_riddle(system_scope(), %{
                 description: "What gets wetter the more it dries?",
                 answer: "towel"
               })

      assert practice.description == "What gets wetter the more it dries?"
      assert practice.answer == "towel"
    end

    test "create_practice_riddle/1 refuses a blank description or answer" do
      assert {:error, changeset} =
               Games.create_practice_riddle(system_scope(), %{description: " ", answer: ""})

      assert %{description: ["can't be blank"], answer: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "create_practice_riddle/1 refuses an answer too long for the tiles" do
      assert {:error, changeset} =
               Games.create_practice_riddle(system_scope(), %{
                 description: "Too long?",
                 answer: String.duplicate("a", 21)
               })

      assert %{answer: ["should be at most 20 character(s)"]} = errors_on(changeset)
    end

    test "create_practice_riddle/1 refuses a description over 500 characters" do
      assert {:error, changeset} =
               Games.create_practice_riddle(system_scope(), %{
                 description: String.duplicate("a", 501),
                 answer: "echo"
               })

      assert %{description: ["should be at most 500 character(s)"]} = errors_on(changeset)
    end

    test "create_practice_riddle/1 trims the outer spaces of both fields" do
      assert {:ok, practice} =
               Games.create_practice_riddle(system_scope(), %{
                 description: "  What has hands?\n",
                 answer: " a clock "
               })

      assert practice.description == "What has hands?"
      assert practice.answer == "a clock"
    end

    test "list_practice_riddles/0 returns them in the order they were added" do
      first = practice_fixture("echo")
      second = practice_fixture("towel")

      assert Games.list_practice_riddles() == [first, second]
    end

    test "update_practice_riddle/2 changes the answer, which get_practice_riddle!/1 then returns" do
      practice = practice_fixture("ecko")

      assert {:ok, _practice} =
               Games.update_practice_riddle(system_scope(), practice, %{answer: "echo"})

      assert Games.get_practice_riddle!(practice.id).answer == "echo"
    end

    test "delete_practice_riddle/1 removes it" do
      practice = practice_fixture("poof")

      assert {:ok, _practice} = Games.delete_practice_riddle(system_scope(), practice)
      assert Games.list_practice_riddles() == []
    end

    test "random_practice_riddle/1 returns nil when there are none" do
      assert Games.random_practice_riddle() == nil
    end

    test "random_practice_riddle/1 picks one of the practice riddles" do
      echo = practice_fixture("echo")
      towel = practice_fixture("towel")

      assert Games.random_practice_riddle() in [echo, towel]
    end

    test "random_practice_riddle/1 never picks the excluded one" do
      echo = practice_fixture("echo")
      towel = practice_fixture("towel")

      for _ <- 1..10, do: assert(Games.random_practice_riddle(echo.id) == towel)
    end

    test "random_practice_riddle/1 returns nil when the excluded one is the only one" do
      echo = practice_fixture("echo")

      assert Games.random_practice_riddle(echo.id) == nil
    end

    test "count_practice_riddles/0 counts them" do
      assert Games.count_practice_riddles() == 0

      practice_fixture("echo")
      practice_fixture("towel")

      assert Games.count_practice_riddles() == 2
    end

    test "practice_riddle_number/1 gives its place in the order they were added" do
      echo = practice_fixture("echo")
      towel = practice_fixture("towel")
      clock = practice_fixture("clock")
      {:ok, _} = Games.delete_practice_riddle(system_scope(), towel)

      assert Games.practice_riddle_number(echo) == 1
      assert Games.practice_riddle_number(clock) == 2
    end

    defp practice_fixture(answer) do
      {:ok, practice} =
        Games.create_practice_riddle(system_scope(), %{
          description: "What am I? (#{answer})",
          answer: answer
        })

      practice
    end
  end
end
