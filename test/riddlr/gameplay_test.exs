defmodule Riddlr.GameplayTest do
  use ExUnit.Case, async: false

  alias Riddlr.Gameplay

  # Clean up ETS tables between tests using a unique riddle_id per test
  defp unique_riddle_id, do: :erlang.unique_integer([:positive])
  defp unique_user_id, do: :erlang.unique_integer([:positive])

  describe "validate_answer/2" do
    test "returns true for exact match" do
      riddle = %{answers: ["keyboard"]}
      assert Gameplay.validate_answer(riddle, "keyboard") == true
    end

    test "case-insensitive matching" do
      riddle = %{answers: ["keyboard"]}
      assert Gameplay.validate_answer(riddle, "KEYBOARD") == true
      assert Gameplay.validate_answer(riddle, "Keyboard") == true
    end

    test "trims whitespace" do
      riddle = %{answers: ["keyboard"]}
      assert Gameplay.validate_answer(riddle, "  keyboard  ") == true
    end

    test "returns false for wrong answer" do
      riddle = %{answers: ["keyboard"]}
      assert Gameplay.validate_answer(riddle, "mouse") == false
    end

    test "matches any answer in the list" do
      riddle = %{answers: ["keyboard", "a keyboard"]}
      assert Gameplay.validate_answer(riddle, "a keyboard") == true
    end
  end

  describe "check_cooldown/2" do
    test "allows first submission" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      assert Gameplay.check_cooldown(rid, uid) == :ok
    end

    test "blocks submission within 1 second" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      :ok = Gameplay.check_cooldown(rid, uid)
      assert Gameplay.check_cooldown(rid, uid) == {:error, :cooldown}
    end

    test "allows submission after cooldown via timestamp override" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      # Record a timestamp in the past (>1s ago)
      past = System.monotonic_time(:microsecond) - 2_000_000
      :ets.insert(:answer_cooldowns, {{rid, uid}, past})
      assert Gameplay.check_cooldown(rid, uid) == :ok
    end

    test "cooldown is per-user per-riddle" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      :ok = Gameplay.check_cooldown(rid, uid1)
      # Different user, different key — should be allowed
      assert Gameplay.check_cooldown(rid, uid2) == :ok
    end
  end

  describe "check_already_solved/2" do
    test "returns :ok when no answers exist" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      assert Gameplay.check_already_solved(rid, uid) == :ok
    end

    test "returns :ok when only incorrect answers exist" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "wrong", false)
      assert Gameplay.check_already_solved(rid, uid) == :ok
    end

    test "returns {:error, :already_solved} after a correct answer" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "correct answer", true)
      assert Gameplay.check_already_solved(rid, uid) == {:error, :already_solved}
    end
  end

  describe "store_answer/4" do
    test "returns a microsecond timestamp" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      ts = Gameplay.store_answer(rid, uid, "answer", false)
      assert is_integer(ts)
    end

    test "allows multiple answers per user" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "wrong1", false)
      Gameplay.store_answer(rid, uid, "wrong2", false)
      entries = :ets.lookup(:riddle_answers, {rid, uid})
      assert length(entries) == 2
    end
  end

  describe "calculate_placement/2" do
    test "first correct answer gets placement 1" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      ts = Gameplay.store_answer(rid, uid, "answer", true)
      assert Gameplay.calculate_placement(rid, ts) == 1
    end

    test "second correct answer gets placement 2" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      # Insert uid1's answer directly with a past timestamp to guarantee uid2 is later
      past_ts = System.monotonic_time(:microsecond) - 1000
      :ets.insert(:riddle_answers, {{rid, uid1}, "answer", past_ts, true})
      ts2 = Gameplay.store_answer(rid, uid2, "answer", true)
      assert Gameplay.calculate_placement(rid, ts2) == 2
    end

    test "incorrect answers don't count toward placement" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      Gameplay.store_answer(rid, uid1, "wrong", false)
      ts2 = Gameplay.store_answer(rid, uid2, "answer", true)
      assert Gameplay.calculate_placement(rid, ts2) == 1
    end
  end

  describe "points_for_placement/1" do
    test "1st place gets 10 points" do
      assert Gameplay.points_for_placement(1) == 10
    end

    test "2nd place gets 9 points" do
      assert Gameplay.points_for_placement(2) == 9
    end

    test "3rd place gets 8 points" do
      assert Gameplay.points_for_placement(3) == 8
    end

    test "4th place gets 7 points, 11th and beyond gets 0 points" do
      assert Gameplay.points_for_placement(4) == 7
      assert Gameplay.points_for_placement(100) == 0
    end
  end

  describe "get_answers/1" do
    test "returns empty list when no answers exist" do
      rid = unique_riddle_id()
      assert Gameplay.get_answers(rid) == []
    end

    test "returns answers sorted by timestamp" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      past_ts = System.monotonic_time(:microsecond) - 1000
      :ets.insert(:riddle_answers, {{rid, uid1}, "first", past_ts, false})
      ts2 = Gameplay.store_answer(rid, uid2, "second", true)
      answers = Gameplay.get_answers(rid)
      assert length(answers) == 2
      assert hd(answers).timestamp == past_ts
      assert List.last(answers).timestamp == ts2
    end

    test "includes user_id, text, timestamp, correct fields" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      ts = Gameplay.store_answer(rid, uid, "keyboard", true)
      [answer] = Gameplay.get_answers(rid)
      assert answer.user_id == uid
      assert answer.text == "keyboard"
      assert answer.timestamp == ts
      assert answer.correct == true
    end
  end

  describe "broadcast_answer/2" do
    test "broadcasts :answer_submitted to the riddle's topic" do
      rid = unique_riddle_id()
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{rid}:answer_submitted")
      answer_data = %{user_id: 1, text: "keyboard", correct: true}
      Gameplay.broadcast_answer(rid, answer_data)
      assert_receive {:answer_submitted, ^answer_data}
    end
  end

  describe "broadcast_answer_flagged/2" do
    test "broadcasts :answer_flagged to the riddle's topic" do
      rid = unique_riddle_id()
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{rid}:answer_flagged")
      Gameplay.broadcast_answer_flagged(rid, "some-answer-id")
      assert_receive {:answer_flagged, "some-answer-id"}
    end
  end

  describe "moderate_answer_async/3" do
    test "broadcasts :answer_flagged when text contains a blocked word" do
      rid = unique_riddle_id()
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{rid}:answer_flagged")
      Gameplay.moderate_answer_async(rid, "answer-123", "this is spam")
      assert_receive {:answer_flagged, "answer-123"}, 500
    end

    test "does not broadcast :answer_flagged for clean text" do
      rid = unique_riddle_id()
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{rid}:answer_flagged")
      Gameplay.moderate_answer_async(rid, "answer-456", "the eiffel tower")
      refute_receive {:answer_flagged, _}, 200
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
      Gameplay.store_answer(rid, uid, "wrong", false)

      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 0.0, 0.01
    end

    test "returns 100.0 when the only player solved it" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "correct", true)

      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 100.0, 0.01
    end

    test "calculates partial completion rate correctly" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      Gameplay.store_answer(rid, uid1, "correct", true)
      Gameplay.store_answer(rid, uid2, "wrong", false)

      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 50.0, 0.01
    end

    test "counts each user only once even with multiple submissions" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "wrong1", false)
      Gameplay.store_answer(rid, uid, "correct", true)

      # 1 unique player, 1 unique solver
      assert %{completion_rate: rate} = Gameplay.get_completion_stats(rid)
      assert_in_delta rate, 100.0, 0.01
    end
  end

  describe "get_top_solvers/2" do
    test "returns empty list when no correct answers" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "wrong", false)

      assert Gameplay.get_top_solvers(rid) == []
    end

    test "returns single solver with placement 1 and correct points" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "correct", true)

      [solver] = Gameplay.get_top_solvers(rid)
      assert solver.user_id == uid
      assert solver.placement == 1
      assert solver.points == 10
    end

    test "orders solvers by timestamp (fastest first)" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()

      # uid1 answered first (past timestamp)
      past_ts = System.monotonic_time(:microsecond) - 1000
      :ets.insert(:riddle_answers, {{rid, uid1}, "correct", past_ts, true})
      Gameplay.store_answer(rid, uid2, "correct", true)

      [first, second] = Gameplay.get_top_solvers(rid)
      assert first.user_id == uid1
      assert first.placement == 1
      assert second.user_id == uid2
      assert second.placement == 2
    end

    test "respects limit parameter" do
      rid = unique_riddle_id()

      for _ <- 1..5 do
        uid = unique_user_id()
        Gameplay.store_answer(rid, uid, "correct", true)
      end

      result = Gameplay.get_top_solvers(rid, 3)
      assert length(result) == 3
    end

    test "ignores incorrect answers" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      Gameplay.store_answer(rid, uid1, "wrong", false)
      Gameplay.store_answer(rid, uid2, "correct", true)

      [solver] = Gameplay.get_top_solvers(rid)
      assert solver.user_id == uid2
      assert solver.placement == 1
    end
  end

  describe "cleanup_riddle/1" do
    test "removes all answers for the riddle" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid, uid, "answer", true)
      :ets.insert(:answer_cooldowns, {{rid, uid}, System.monotonic_time(:microsecond)})

      Gameplay.cleanup_riddle(rid)

      assert :ets.lookup(:riddle_answers, {rid, uid}) == []
      assert :ets.lookup(:answer_cooldowns, {rid, uid}) == []
    end

    test "does not affect other riddles" do
      rid1 = unique_riddle_id()
      rid2 = unique_riddle_id()
      uid = unique_user_id()
      Gameplay.store_answer(rid1, uid, "answer", true)
      Gameplay.store_answer(rid2, uid, "answer", true)

      Gameplay.cleanup_riddle(rid1)

      assert :ets.lookup(:riddle_answers, {rid1, uid}) == []
      assert length(:ets.lookup(:riddle_answers, {rid2, uid})) == 1
    end
  end
end
