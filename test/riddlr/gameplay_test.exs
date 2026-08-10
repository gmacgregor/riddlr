defmodule Riddlr.GameplayTest do
  use ExUnit.Case, async: false

  alias Riddlr.Gameplay

  # Clean up ETS tables between tests using a unique riddle_id per test
  defp unique_riddle_id, do: :erlang.unique_integer([:positive])
  defp unique_user_id, do: :erlang.unique_integer([:positive])

  # Seeds the answers table directly — these are read-side functions, and the
  # write side is only reachable through Gameplay.submit_answer/3.
  defp seed_answer(rid, uid, text, correct?, ts \\ nil) do
    ts = ts || System.monotonic_time(:microsecond)
    :ets.insert(:riddle_answers, {{rid, uid}, text, ts, correct?, nil})
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

    test "includes user_id, text, timestamp, correct fields" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      ts = seed_answer(rid, uid, "keyboard", true)
      [answer] = Gameplay.get_answers(rid)
      assert answer.user_id == uid
      assert answer.text == "keyboard"
      assert answer.timestamp == ts
      assert answer.correct == true
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

  describe "get_top_solvers/2" do
    test "returns empty list when no correct answers" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "wrong", false)

      assert Gameplay.get_top_solvers(rid) == []
    end

    test "returns single solver with placement 1 and correct points" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "correct", true)

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
      seed_answer(rid, uid1, "correct", true, past_ts)
      seed_answer(rid, uid2, "correct", true)

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
        seed_answer(rid, uid, "correct", true)
      end

      result = Gameplay.get_top_solvers(rid, 3)
      assert length(result) == 3
    end

    test "ignores incorrect answers" do
      rid = unique_riddle_id()
      uid1 = unique_user_id()
      uid2 = unique_user_id()
      seed_answer(rid, uid1, "wrong", false)
      seed_answer(rid, uid2, "correct", true)

      [solver] = Gameplay.get_top_solvers(rid)
      assert solver.user_id == uid2
      assert solver.placement == 1
    end
  end

  describe "cleanup_riddle/1" do
    test "removes all answers for the riddle" do
      rid = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid, uid, "answer", true)
      :ets.insert(:answer_cooldowns, {{rid, uid}, System.monotonic_time(:microsecond)})

      Gameplay.cleanup_riddle(rid)

      assert :ets.lookup(:riddle_answers, {rid, uid}) == []
      assert :ets.lookup(:answer_cooldowns, {rid, uid}) == []
    end

    test "does not affect other riddles" do
      rid1 = unique_riddle_id()
      rid2 = unique_riddle_id()
      uid = unique_user_id()
      seed_answer(rid1, uid, "answer", true)
      seed_answer(rid2, uid, "answer", true)

      Gameplay.cleanup_riddle(rid1)

      assert :ets.lookup(:riddle_answers, {rid1, uid}) == []
      assert length(:ets.lookup(:riddle_answers, {rid2, uid})) == 1
    end
  end
end
