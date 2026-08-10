defmodule Riddlr.Games.RiddleTest do
  use ExUnit.Case, async: true

  alias Riddlr.Games.Riddle

  describe "valid_transitions/0" do
    test "exposes the play status transition table" do
      table = Riddle.valid_transitions()

      assert table["closed"] == ["scheduled"]
      assert table["live"] == ["completed"]
      assert table["archived"] == []
      assert Map.keys(table) |> Enum.sort() == Enum.sort(Riddle.play_statuses())
    end
  end

  describe "can_transition?/2" do
    test "true for a permitted transition" do
      assert Riddle.can_transition?("scheduled", "ready")
    end

    test "false for a forbidden transition" do
      refute Riddle.can_transition?("closed", "live")
    end

    test "false for an unknown status" do
      refute Riddle.can_transition?("bogus", "ready")
    end

    test "accepts atom targets" do
      assert Riddle.can_transition?("live", :completed)
      refute Riddle.can_transition?("live", :archived)
    end
  end
end
