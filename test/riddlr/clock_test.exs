defmodule Riddlr.ClockTest do
  # Frozen clock state is global — these tests cannot run alongside anything
  # that reads the clock.
  use ExUnit.Case, async: false

  alias Riddlr.Clock

  describe "unfrozen" do
    test "utc_now/0 tracks the system clock" do
      before = DateTime.utc_now()
      now = Clock.utc_now()

      assert DateTime.compare(now, before) in [:eq, :gt]
      assert DateTime.diff(now, before, :second) < 2
    end

    test "monotonic_us/0 advances with real time" do
      first = Clock.monotonic_us()
      Process.sleep(1)

      assert Clock.monotonic_us() > first
    end
  end

  describe "frozen" do
    test "utc_now/0 returns the frozen instant on every read" do
      instant = ~U[2026-08-01 12:00:00.000000Z]
      Clock.Frozen.freeze(instant)

      assert Clock.utc_now() == instant
      Process.sleep(2)
      assert Clock.utc_now() == instant
    end

    test "monotonic_us/0 stands still" do
      Clock.Frozen.freeze()

      first = Clock.monotonic_us()
      Process.sleep(2)

      assert Clock.monotonic_us() == first
    end

    test "advance/2 moves wall-clock and monotonic time together" do
      Clock.Frozen.freeze(~U[2026-08-01 12:00:00.000000Z])
      mono = Clock.monotonic_us()

      Clock.Frozen.advance(3, :second)

      assert Clock.utc_now() == ~U[2026-08-01 12:00:03.000000Z]
      assert Clock.monotonic_us() == mono + 3_000_000
    end

    test "advance/2 also understands minutes, hours and days" do
      Clock.Frozen.freeze(~U[2026-08-01 12:00:00.000000Z])

      Clock.Frozen.advance(90, :minute)
      Clock.Frozen.advance(2, :hour)
      Clock.Frozen.advance(1, :day)

      assert Clock.utc_now() == ~U[2026-08-02 15:30:00.000000Z]
    end

    test "the frozen clock is visible from other processes" do
      Clock.Frozen.freeze(~U[2026-08-01 12:00:00.000000Z])

      task = Task.async(fn -> Clock.utc_now() end)

      assert Task.await(task) == ~U[2026-08-01 12:00:00.000000Z]
    end

    test "unfreeze/0 hands control back to the system clock" do
      Clock.Frozen.freeze(~U[2026-08-01 12:00:00.000000Z])
      Clock.Frozen.unfreeze()

      assert DateTime.diff(Clock.utc_now(), DateTime.utc_now(), :second) < 2
    end

    test "freezing is undone when the test that froze it ends" do
      # Registered by freeze/1 — asserted by the unfrozen tests above, which
      # would fail if any frozen state leaked out of this describe block.
      Clock.Frozen.freeze()
      assert Clock.Frozen.frozen?()
    end

    test "freeze/1 rejects an instant that is not UTC" do
      eastern = DateTime.from_naive!(~N[2026-08-01 08:00:00], "America/New_York")

      assert_raise ArgumentError, ~r/UTC/, fn -> Clock.Frozen.freeze(eastern) end
      refute Clock.Frozen.frozen?()
    end

    test "freeze/1 rejects anything that is not a DateTime" do
      assert_raise ArgumentError, ~r/UTC DateTime/, fn ->
        Clock.Frozen.freeze(~N[2026-08-01 12:00:00])
      end

      refute Clock.Frozen.frozen?()
    end
  end

  describe "the seam" do
    @forbidden ~r/(DateTime|NaiveDateTime)\.utc_now|Date\.utc_today|System\.(monotonic_time|system_time)\(/

    test "no module outside the clock adapters reads the runtime clock" do
      offenders =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.reject(&(&1 in ["lib/riddlr/clock.ex", "lib/riddlr/clock/system.ex"]))
        |> Enum.filter(&(File.read!(&1) =~ @forbidden))

      assert offenders == [],
             """
             These modules read the clock directly instead of going through
             Riddlr.Clock, which puts them beyond the reach of a frozen clock:

             #{Enum.map_join(offenders, "\n", &("  " <> &1))}
             """
    end
  end
end
