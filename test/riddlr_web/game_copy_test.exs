defmodule RiddlrWeb.GameCopyTest do
  use ExUnit.Case, async: true

  alias RiddlrWeb.GameCopy

  describe "counts" do
    test "group thousands with commas" do
      assert GameCopy.room_count(0) == "0 here"
      assert GameCopy.room_count(999) == "999 here"
      assert GameCopy.room_count(1000) == "1,000 here"
      assert GameCopy.room_more(1_234_567) == "…and 1,234,567 more"
      assert GameCopy.ticker_tail(2500) == " and 2,500 others just joined"
    end
  end

  describe "play" do
    test "ordinal handles teens and twenties" do
      assert Enum.map([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111], &GameCopy.ordinal/1) ==
               ~w(1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd 101st 111th)
    end

    test "guess count" do
      assert GameCopy.guess_count(0) == "0 guesses"
      assert GameCopy.guess_count(1) == "1 guess"
      assert GameCopy.guess_count(1200) == "1,200 guesses"
    end

    test "solved count" do
      assert GameCopy.solved_count(0) == "0 solved"
      assert GameCopy.solved_count(1200) == "1,200 solved"
    end

    test "M:SS clock" do
      assert GameCopy.m_ss(0) == "0:00"
      assert GameCopy.m_ss(45) == "0:45"
      assert GameCopy.m_ss(270) == "4:30"
      assert GameCopy.m_ss(-3) == "0:00"
    end

    test "solved title by place and points" do
      assert GameCopy.solved_title(1, 10) == "First! Nobody was faster."
      assert GameCopy.solved_title(2, 9) == "Cracked it. 2nd place."
      assert GameCopy.solved_title(11, 0) == "Cracked it — just off the board."
    end

    test "quip never repeats the last one" do
      for last <- GameCopy.quips() do
        assert GameCopy.quip(last) != last
      end
    end
  end
end
