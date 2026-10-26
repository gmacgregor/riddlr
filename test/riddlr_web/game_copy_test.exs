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
end
