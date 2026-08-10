defmodule Riddlr.Clock do
  @moduledoc """
  Ask here what time it is. Don't ask the runtime.

  Riddlr is a game about seconds. A cooldown is a second. Placement is decided
  by who got there first. Both countdowns, the lobby's and the solve timer's,
  are just subtraction against a Live date. When every one of those reads the
  system clock directly, the test suite has to race real time to say anything
  about them — and it loses, quietly, on a loaded CI box.

  So time comes in through here. In production that's `Riddlr.Clock.System`,
  which does the obvious thing. In tests it's `Riddlr.Clock.Frozen`, which lets
  you pin the clock to an instant and walk it forward a second at a time:

      Frozen.freeze(riddle.live_date)
      {:correct, 1, 10} = Gameplay.submit_answer(riddle, alice, "keyboard")
      Frozen.advance(1, :second)
      {:correct, 2, 9} = Gameplay.submit_answer(riddle, bob, "keyboard")

  Two things to keep in mind.

  First, the seam only works if everyone uses it. One stray `DateTime.utc_now/0`
  somewhere in `lib/` is a piece of the app a frozen clock can't reach, and it
  will be the piece that flakes. `Riddlr.ClockTest` greps for those and fails.

  Second, pick the right hand of the clock. `utc_now/0` is wall-clock time — use
  it for anything a player sees or the database stores. `monotonic_us/0` is for
  ordering and "how long did that take", and it's the one that doesn't lurch
  when the wall clock is adjusted underneath you. They're separate readings, not
  two views of one number, so never subtract one from the other.
  """

  @callback utc_now() :: DateTime.t()
  @callback monotonic_us() :: integer()

  @doc """
  What time is it, right now, in UTC.
  """
  def utc_now, do: adapter().utc_now()

  @doc """
  A microsecond counter that only ever goes up.

  Good for ordering events and measuring how long something took. Useless as a
  date — the number means nothing except next to another reading from here.
  """
  def monotonic_us, do: adapter().monotonic_us()

  defp adapter, do: Application.get_env(:riddlr, :clock, Riddlr.Clock.System)
end
