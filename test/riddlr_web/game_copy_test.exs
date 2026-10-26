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

  describe "results" do
    test "solve time in seconds with one decimal" do
      assert GameCopy.solve_secs(3_456) == "3.5s"
      assert GameCopy.solve_secs(12_000) == "12.0s"
      assert GameCopy.solve_secs(nil) == "—"
    end

    test "you card for a viewer who did not join" do
      assert GameCopy.you_card(nil, false) == %{
               stamp: "—",
               none?: true,
               title: "You weren't in this one",
               sub: "Join the next lobby to get on the board."
             }
    end

    test "you card for a viewer who guessed but did not solve" do
      assert GameCopy.you_card(nil, true) == %{
               stamp: "0",
               none?: true,
               title: "Not this time",
               sub: "No points, but you know it now. Next one's yours."
             }
    end

    test "you card for the winner" do
      assert GameCopy.you_card(%{placement: 1, points: 10}, true) == %{
               stamp: "1ST",
               none?: false,
               title: "You won it",
               sub: "+10 pts for this riddle"
             }
    end

    test "you card for a scoring place" do
      assert GameCopy.you_card(%{placement: 3, points: 8}, true) == %{
               stamp: "3RD",
               none?: false,
               title: "You placed 3rd",
               sub: "+8 pts for this riddle"
             }
    end

    test "you card for a solve outside the top 10" do
      assert GameCopy.you_card(%{placement: 11, points: 0}, true) == %{
               stamp: "11TH",
               none?: true,
               title: "You placed 11th",
               sub: "Solved, but outside the top 10."
             }
    end
  end
end
