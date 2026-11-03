defmodule Riddlr.Clock.SystemTest do
  use ExUnit.Case, async: true

  alias Riddlr.Clock

  test "utc_now/0 reads the runtime's UTC time" do
    before = DateTime.utc_now()
    now = Clock.System.utc_now()

    assert now.time_zone == "Etc/UTC"
    assert DateTime.compare(now, before) in [:eq, :gt]
    assert DateTime.diff(now, before, :second) < 2
  end

  test "monotonic_us/0 never goes backwards" do
    readings = for _ <- 1..100, do: Clock.System.monotonic_us()

    assert readings == Enum.sort(readings)
  end

  test "monotonic_us/0 counts in microseconds" do
    before = System.monotonic_time(:microsecond)
    reading = Clock.System.monotonic_us()

    assert reading >= before
    assert reading - before < 1_000_000
  end
end
