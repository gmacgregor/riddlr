defmodule RiddlrWeb.DropTimeTest do
  use ExUnit.Case, async: true

  alias RiddlrWeb.DropTime

  # Eastern noon on 2030-01-01, so drops on later days read as dates.
  @now ~U[2030-01-01 17:00:00Z]

  describe "short/2" do
    test "gives the Eastern date and time in winter" do
      assert DropTime.short(~U[2030-01-08 18:17:00Z], @now) == "Jan 8, 1:17pm EST"
    end

    test "follows daylight time in summer" do
      assert DropTime.short(~U[2030-07-08 17:17:00Z], @now) == "Jul 8, 1:17pm EDT"
    end

    test "writes midnight, noon and single-digit minutes in the 12-hour form" do
      assert DropTime.short(~U[2030-01-08 05:00:00Z], @now) == "Jan 8, 12:00am EST"
      assert DropTime.short(~U[2030-01-08 17:00:00Z], @now) == "Jan 8, 12:00pm EST"
      assert DropTime.short(~U[2030-01-08 18:05:00Z], @now) == "Jan 8, 1:05pm EST"
    end

    test "uses the Eastern date when the UTC date is a day later" do
      assert DropTime.short(~U[2030-01-09 02:30:00Z], @now) == "Jan 8, 9:30pm EST"
    end

    test "switches zone on the DST change days" do
      # 2030-03-10 and 2030-11-03 are the change days.
      assert DropTime.short(~U[2030-03-10 06:59:00Z], @now) == "Mar 10, 1:59am EST"
      assert DropTime.short(~U[2030-03-10 07:00:00Z], @now) == "Mar 10, 3:00am EDT"
      assert DropTime.short(~U[2030-11-03 05:59:00Z], @now) == "Nov 3, 1:59am EDT"
      assert DropTime.short(~U[2030-11-03 06:00:00Z], @now) == "Nov 3, 1:00am EST"
    end

    test "says Today for a drop later on the same Eastern day" do
      assert DropTime.short(~U[2030-01-01 18:17:00Z], @now) == "Today at 1:17pm EST"
    end

    test "says Tomorrow for a drop on the next Eastern day" do
      assert DropTime.short(~U[2030-01-02 18:17:00Z], @now) == "Tomorrow at 1:17pm EST"
    end

    test "judges the day in Eastern, not UTC" do
      # 9pm Eastern on Jan 1 is already Jan 2 in UTC, yet still "today".
      late = ~U[2030-01-02 02:00:00Z]
      assert DropTime.short(late, @now) == "Today at 9:00pm EST"
      # From 9pm Eastern on Jan 1, 1am Eastern on Jan 2 is tomorrow.
      assert DropTime.short(~U[2030-01-02 06:00:00Z], late) == "Tomorrow at 1:00am EST"
    end

    test "gives the date two or more days out" do
      assert DropTime.short(~U[2030-01-03 18:17:00Z], @now) == "Jan 3, 1:17pm EST"
    end
  end

  describe "long/3" do
    test "gives the weekday apart from the date and time" do
      assert DropTime.long(~U[2030-11-04 18:17:00Z], @now) ==
               %DropTime.Long{lead: "Monday, ", marked: "Nov 4, 1:17pm EST"}
    end

    test "gives no weekday for Today or Tomorrow" do
      assert DropTime.long(~U[2030-01-01 18:17:00Z], @now) ==
               %DropTime.Long{lead: "", marked: "Today at 1:17pm EST"}

      assert %DropTime.Long{marked: "Tomorrow" <> _} =
               DropTime.long(~U[2030-01-02 18:17:00Z], @now)
    end
  end

  describe "mid_sentence: true" do
    test "lowercases Today and Tomorrow" do
      opts = [mid_sentence: true]

      assert DropTime.short(~U[2030-01-01 18:17:00Z], @now, opts) == "today at 1:17pm EST"

      assert %DropTime.Long{marked: "tomorrow" <> _} =
               DropTime.long(~U[2030-01-02 18:17:00Z], @now, opts)
    end

    test "leaves dates as they are" do
      assert DropTime.short(~U[2030-01-08 18:17:00Z], @now, mid_sentence: true) ==
               "Jan 8, 1:17pm EST"
    end
  end

  describe "day/1" do
    test "gives the Eastern date, never a relative word" do
      assert DropTime.day(~U[2030-01-01 17:00:00Z]) == "Tue, Jan 1"
      assert DropTime.day(~U[2030-01-02 02:00:00Z]) == "Tue, Jan 1"
    end
  end
end
