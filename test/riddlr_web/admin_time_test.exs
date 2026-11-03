defmodule RiddlrWeb.AdminTimeTest do
  use ExUnit.Case, async: true

  alias RiddlrWeb.AdminTime

  describe "to_utc_datetime/1" do
    test "reads the input as Eastern time" do
      assert AdminTime.to_utc_datetime("2026-03-10T14:27") == ~U[2026-03-10 18:27:00Z]
    end

    test "takes the first of the two instants when the clocks go back" do
      # 1:30am happens twice on Nov 1 2026: first in EDT, then in EST.
      assert AdminTime.to_utc_datetime("2026-11-01T01:30") == ~U[2026-11-01 05:30:00Z]
    end

    test "moves a time skipped when the clocks go forward to just after the jump" do
      # 2:30am never happens on Mar 8 2026: clocks jump from 2:00 EST to 3:00 EDT.
      assert AdminTime.to_utc_datetime("2026-03-08T02:30") == ~U[2026-03-08 07:00:00Z]
    end
  end
end
