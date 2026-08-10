defmodule Riddlr.Gameplay.AnswerTest do
  # Freezing the clock is global — see Riddlr.Clock.Frozen.
  use ExUnit.Case, async: false

  alias Riddlr.Clock.Frozen
  alias Riddlr.Gameplay.Answer

  setup do
    Frozen.freeze()
    :ok
  end

  defp user, do: %{id: 7, username: "ada"}

  describe "new/4" do
    test "stamps the answer with the clock and derives its id from riddle, user and timestamp" do
      answer = Answer.new(42, user(), "keyboard")

      assert answer.riddle_id == 42
      assert answer.user_id == 7
      assert answer.username == "ada"
      assert answer.text == "keyboard"
      assert answer.timestamp == Frozen.monotonic_us()
      assert answer.id == "42-7-#{answer.timestamp}"
    end

    test "defaults to an incorrect, unflagged, non-chat answer" do
      answer = Answer.new(42, user(), "keyboard")

      refute answer.correct
      refute answer.flagged
      refute answer.chat
      refute answer.show_highlight
      assert answer.offset_ms == nil
    end

    test "accepts correct, offset_ms, timestamp and chat overrides" do
      answer =
        Answer.new(42, user(), "hi", correct: true, offset_ms: 1_500, timestamp: 99, chat: true)

      assert answer.correct
      assert answer.offset_ms == 1_500
      assert answer.timestamp == 99
      assert answer.chat
      assert answer.id == "42-7-99"
    end
  end

  describe "ETS layout" do
    test "to_ets/1 stores the row under a riddle/user key" do
      answer = Answer.new(42, user(), "keyboard", correct: true, offset_ms: 1_500, timestamp: 99)

      assert Answer.to_ets(answer) == {{42, 7}, "keyboard", 99, true, 1_500}
    end

    test "from_ets/1 rebuilds the answer, id included" do
      answer = Answer.from_ets({{42, 7}, "keyboard", 99, true, 1_500})

      assert answer.id == "42-7-99"
      assert answer.riddle_id == 42
      assert answer.user_id == 7
      assert answer.text == "keyboard"
      assert answer.timestamp == 99
      assert answer.correct
      assert answer.offset_ms == 1_500
      assert answer.username == nil
    end

    test "a stored answer round-trips, apart from the username ETS never sees" do
      answer = Answer.new(42, user(), "keyboard", correct: true, offset_ms: 1_500)

      assert answer |> Answer.to_ets() |> Answer.from_ets() == %{answer | username: nil}
    end

    test "ets_pattern/1 matches every row for a riddle" do
      assert Answer.ets_pattern(42) == {{42, :_}, :_, :_, :_, :_}
    end

    test "ets_pattern/2 narrows to correct or incorrect rows" do
      assert Answer.ets_pattern(42, true) == {{42, :_}, :_, :_, true, :_}
    end
  end

  describe "topic/1" do
    test "names the answer_submitted topic for a riddle" do
      assert Answer.topic(42) == "gameplay:42:answer_submitted"
    end
  end

  describe "flagged_topic/1" do
    test "names the answer_flagged topic for a riddle" do
      assert Answer.flagged_topic(42) == "gameplay:42:answer_flagged"
    end
  end
end
