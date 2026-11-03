defmodule RiddlrWeb.GameCopyTest do
  # These tests check the rules inside the copy (numbers, ordinals, which
  # branch a case takes), not the wording, so the words can change freely.
  use ExUnit.Case, async: true

  alias RiddlrWeb.GameCopy

  describe "counts" do
    test "group thousands with commas" do
      assert GameCopy.Lobby.room_count(0) =~ whole_number("0")
      assert GameCopy.Lobby.room_count(999) =~ whole_number("999")
      assert GameCopy.Lobby.room_count(1000) =~ whole_number("1,000")
      assert GameCopy.Lobby.room_more(1_234_567) =~ whole_number("1,234,567")
      assert GameCopy.Lobby.ticker_tail(2500) =~ whole_number("2,500")
    end
  end

  describe "riddle_name/1" do
    test "leads with the number when the riddle has one" do
      assert GameCopy.riddle_name(%{number: 12, name: "Echo"}) == "No. 12: Echo"
    end

    test "leaves the number out when there is none" do
      assert GameCopy.riddle_name(%{number: nil, name: "Echo"}) == "Echo"
    end
  end

  describe "riddle_title/1" do
    test "leads with the number when the riddle has one" do
      riddle = %{number: 12, name: "Echo", category: %{name: "What am I"}}
      assert GameCopy.riddle_title(riddle) == "No. 12: Echo · What am I"
    end

    test "leaves the number out when there is none" do
      riddle = %{number: nil, name: "Echo", category: %{name: "What am I"}}
      assert GameCopy.riddle_title(riddle) == "Echo · What am I"
    end
  end

  describe "play" do
    test "ordinal handles teens and twenties" do
      assert Enum.map([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111], &GameCopy.ordinal/1) ==
               ~w(1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd 101st 111th)
    end

    test "guess count is singular for one guess" do
      assert GameCopy.Play.guess_count(0) =~ whole_number("0")
      assert GameCopy.Play.guess_count(1) =~ whole_number("1")
      assert GameCopy.Play.guess_count(1200) =~ whole_number("1,200")

      one = String.replace(GameCopy.Play.guess_count(1), "1", "N")
      two = String.replace(GameCopy.Play.guess_count(2), "2", "N")
      refute one == two
    end

    test "solved count" do
      assert GameCopy.solved_count(0) =~ whole_number("0")
      assert GameCopy.solved_count(1200) =~ whole_number("1,200")
    end

    test "M:SS clock" do
      assert GameCopy.m_ss(0) == "0:00"
      assert GameCopy.m_ss(45) == "0:45"
      assert GameCopy.m_ss(270) == "4:30"
      assert GameCopy.m_ss(-3) == "0:00"
    end

    test "solved title differs for first, a scoring place and off the board" do
      first = GameCopy.Play.solved_title(1, 10)
      second = GameCopy.Play.solved_title(2, 9)
      off_board = GameCopy.Play.solved_title(11, 0)

      assert second =~ GameCopy.ordinal(2)
      assert Enum.uniq([first, second, off_board]) == [first, second, off_board]
    end

    test "solved sub shows the points and the time left" do
      sub = GameCopy.Play.solved_sub(9, 75)

      assert sub =~ "+9"
      assert sub =~ GameCopy.m_ss(75)
    end

    test "quip never repeats the last one" do
      for last <- GameCopy.Play.quips() do
        assert GameCopy.Play.quip(last) != last
      end
    end
  end

  describe "results" do
    test "solve time in seconds with two decimals" do
      assert GameCopy.solve_secs(3_456) == "3.46s"
      assert GameCopy.solve_secs(12_340) == "12.34s"
      assert GameCopy.solve_secs(12_000) == "12.00s"
      assert GameCopy.solve_secs(nil) == "—"
    end

    test "you card for a viewer who did not join" do
      assert %{stamp: "—", none?: true} = GameCopy.Results.you_card(nil, false)
    end

    test "you card for a viewer who guessed but did not solve" do
      card = GameCopy.Results.you_card(nil, true)

      assert %{stamp: "0", none?: true} = card
      refute card.title == GameCopy.Results.you_card(nil, false).title
    end

    test "you card for the winner" do
      card = GameCopy.Results.you_card(%{placement: 1, points: 10}, true)

      assert %{stamp: "1ST", none?: false} = card
      assert card.sub =~ "+10"
    end

    test "you card for a scoring place" do
      card = GameCopy.Results.you_card(%{placement: 3, points: 8}, true)

      assert %{stamp: "3RD", none?: false} = card
      assert card.title =~ GameCopy.ordinal(3)
      assert card.sub =~ "+8"
    end

    test "you card for a solve outside the top 10" do
      card = GameCopy.Results.you_card(%{placement: 11, points: 0}, true)

      assert %{stamp: "11TH", none?: true} = card
      assert card.title =~ GameCopy.ordinal(11)
      refute card.sub == GameCopy.Results.you_card(%{placement: 3, points: 8}, true).sub
    end
  end

  # Matches `n` as a whole number, so "6" does not match inside "16" or "1,600".
  @spec whole_number(String.t()) :: Regex.t()
  defp whole_number(n), do: ~r/(?<![\d,])#{Regex.escape(n)}(?![\d,])/
end
