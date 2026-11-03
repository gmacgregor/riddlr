defmodule Riddlr.GameplayTest do
  use ExUnit.Case, async: false

  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Store

  # Clean up ETS tables between tests using a unique riddle_id per test
  defp unique_riddle_id, do: :erlang.unique_integer([:positive])
  defp unique_user_id, do: :erlang.unique_integer([:positive])

  # Seeds through the Store — these are read-side functions, and
  # Gameplay.submit_answer/3 needs a live riddle and a cooldown.
  defp seed_answer(rid, uid, text, correct?, ts \\ nil) do
    ts = ts || System.monotonic_time(:microsecond)
    user = %{id: uid, username: "user#{uid}"}
    Store.record(Answer.new(rid, user, text, correct: correct?, timestamp: ts))
    ts
  end

  describe "solved?/2" do
    test "false when the user has no answers" do
      assert Gameplay.solved?(unique_riddle_id(), unique_user_id()) == false
    end

    test "false when the user has only incorrect answers" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "wrong", false)
      assert Gameplay.solved?(rid, uid) == false
    end

    test "true once the user has a correct answer" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "correct answer", true)
      assert Gameplay.solved?(rid, uid) == true
    end
  end

  describe "guessed?/2" do
    test "false when the user has no answers" do
      assert Gameplay.guessed?(unique_riddle_id(), unique_user_id()) == false
    end

    test "true once the user has any answer" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "wrong", false)
      assert Gameplay.guessed?(rid, uid) == true
    end

    test "false once the riddle's answers are cleaned up" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "wrong", false)
      Gameplay.cleanup_riddle(rid)
      assert Gameplay.guessed?(rid, uid) == false
    end
  end

  describe "points_table/0" do
    test "the points for places 1 to 10" do
      assert Gameplay.points_table() == [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
    end
  end

  describe "solved_count/1" do
    test "0 for an unknown riddle" do
      assert Gameplay.solved_count(unique_riddle_id()) == 0
    end

    test "counts distinct correct solvers, ignoring wrong guesses" do
      rid = unique_riddle_id()
      first = unique_user_id()
      second = unique_user_id()
      seed_answer(rid, first, "wrong", false)
      seed_answer(rid, first, "correct", true)
      seed_answer(rid, second, "correct", true)
      seed_answer(rid, unique_user_id(), "wrong", false)
      seed_answer(unique_riddle_id(), unique_user_id(), "correct", true)

      assert Gameplay.solved_count(rid) == 2
    end
  end

  describe "live_solve_for/2" do
    test "nil when the user has not solved" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "wrong", false)
      assert Gameplay.live_solve_for(rid, uid) == nil
    end

    test "the user's placement and points" do
      rid = unique_riddle_id()
      first = unique_user_id()
      second = unique_user_id()
      ts = System.monotonic_time(:microsecond)
      seed_answer(rid, first, "correct", true, ts - 1000)
      seed_answer(rid, second, "wrong", false, ts - 500)
      seed_answer(rid, second, "correct", true, ts)

      assert Gameplay.live_solve_for(rid, second) == %{placement: 2, points: 9}
    end
  end

  describe "get_answers/1" do
    test "returns empty list when no answers exist" do
      rid = unique_riddle_id()
      assert Gameplay.get_answers(rid) == []
    end

    test "returns answers sorted by timestamp (newest first)" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      past_ts = System.monotonic_time(:microsecond) - 1000
      seed_answer(rid, uid1, "first", false, past_ts)
      ts2 = seed_answer(rid, uid2, "second", true)
      answers = Gameplay.get_answers(rid)
      assert length(answers) == 2
      assert hd(answers).timestamp == ts2
      assert List.last(answers).timestamp == past_ts
    end

    test "includes user_id, username, text, timestamp, correct, placement fields" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      ts = seed_answer(rid, uid, "keyboard", true)
      [answer] = Gameplay.get_answers(rid)
      assert answer.user_id == uid
      assert answer.username == "user#{uid}"
      assert answer.text == "keyboard"
      assert answer.timestamp == ts
      assert answer.correct == true
      assert answer.placement == 1
    end

    test "takes only the newest `limit` answers" do
      rid = unique_riddle_id()
      ts = System.monotonic_time(:microsecond)
      for n <- 1..3, do: seed_answer(rid, unique_user_id(), "guess", false, ts + n)

      assert rid |> Gameplay.get_answers(2) |> Enum.map(& &1.timestamp) == [ts + 3, ts + 2]
    end
  end

  describe "get_live_feed/2" do
    test "returns the newest answers, oldest first, with correct ones masked" do
      rid = unique_riddle_id()
      seed_answer(rid, unique_user_id(), "first", false, 1)
      seed_answer(rid, unique_user_id(), "second", false, 2)
      seed_answer(rid, unique_user_id(), "right", true, 3)

      assert [%{text: "second"}, %{text: nil, correct: true}] = Gameplay.get_live_feed(rid, 2)
    end
  end

  describe "subscribe_answers/1" do
    test "delivers answer batches for the riddle" do
      rid = unique_riddle_id()
      :ok = Gameplay.subscribe_answers(rid)

      Gameplay.broadcast_answers(rid, [])

      assert_receive {:answers_batch, [], _totals}
    end
  end

  describe "get_completion_stats/1" do
    test "returns 0.0 completion_rate when no answers exist" do
      rid = unique_riddle_id()
      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 0.0, 0.01
    end

    test "returns 0.0 when all answers are incorrect" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "wrong", false)

      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 0.0, 0.01
    end

    test "returns 100.0 when the only player solved it" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "correct", true)

      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 100.0, 0.01
    end

    test "calculates partial completion rate correctly" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      seed_answer(rid, uid1, "correct", true)
      seed_answer(rid, uid2, "wrong", false)

      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 50.0, 0.01
    end

    test "counts each user only once even with multiple submissions" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "wrong1", false)
      seed_answer(rid, uid, "correct", true)

      # 1 unique player, 1 unique solver
      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 100.0, 0.01
    end
  end

  describe "solve_rows/1" do
    test "returns no rows when no correct answers" do
      rid = unique_riddle_id()
      seed_answer(rid, unique_user_id(), "wrong", false)

      assert Gameplay.solve_rows(rid) == []
    end

    test "orders solvers by the placement each claimed, ignoring wrong guesses" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      seed_answer(rid, unique_user_id(), "wrong", false)
      seed_answer(rid, uid1, "correct", true)
      seed_answer(rid, uid2, "correct", true)

      assert [
               %{riddle_id: ^rid, user_id: ^uid1, placement: 1, points: 10},
               %{user_id: ^uid2, placement: 2, points: 9}
             ] = Gameplay.solve_rows(rid)
    end
  end

  describe "entry_rows/1" do
    test "returns one row per distinct guesser, solvers included" do
      rid = unique_riddle_id()
      solver = unique_user_id()
      guesser = unique_user_id()
      seed_answer(rid, guesser, "wrong", false)
      seed_answer(rid, guesser, "also wrong", false)
      seed_answer(rid, solver, "wrong", false)
      seed_answer(rid, solver, "correct", true)
      seed_answer(unique_riddle_id(), unique_user_id(), "other riddle", false)

      rows = Gameplay.entry_rows(rid)

      assert rows |> Enum.map(& &1.user_id) |> Enum.sort() == Enum.sort([solver, guesser])
      assert Enum.all?(rows, &(&1.riddle_id == rid and is_struct(&1.inserted_at, DateTime)))
    end

    test "returns no rows when nobody guessed" do
      assert Gameplay.entry_rows(unique_riddle_id()) == []
    end
  end

  describe "cleanup_riddle/1" do
    test "removes all answers for the riddle" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "answer", true)
      :ok = Store.claim_cooldown({rid, uid}, 1_000_000)

      Gameplay.cleanup_riddle(rid)

      assert Gameplay.get_answers(rid) == []
      refute Gameplay.guessed?(rid, uid)
      assert :ok = Store.claim_cooldown({rid, uid}, 1_000_000)
    end

    test "does not affect other riddles" do
      rid1 = unique_riddle_id()
      rid2 = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid1, uid, "answer", true)
      seed_answer(rid2, uid, "answer", true)

      Gameplay.cleanup_riddle(rid1)

      assert Gameplay.get_answers(rid1) == []
      assert [_] = Gameplay.get_answers(rid2)
    end
  end
end
