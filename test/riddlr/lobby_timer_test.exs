defmodule Riddlr.LobbyTimerTest do
  # Freezes the clock — must not run alongside other clock readers.
  use ExUnit.Case, async: false

  alias Riddlr.Clock.Frozen
  alias Riddlr.LobbyTimer

  setup do
    riddle_id = :erlang.unique_integer([:positive])
    now = ~U[2026-08-01 12:00:00.000000Z]
    Frozen.freeze(now)
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "game:lobby:#{riddle_id}")

    %{riddle_id: riddle_id, now: now}
  end

  test "broadcasts the seconds left as soon as it starts", %{riddle_id: riddle_id, now: now} do
    :ok = LobbyTimer.ensure_started(riddle_id, DateTime.add(now, 120, :second))

    assert_receive {:countdown_tick, 120}
  end

  test "each tick broadcasts the seconds left on the frozen clock", %{
    riddle_id: riddle_id,
    now: now
  } do
    :ok = LobbyTimer.ensure_started(riddle_id, DateTime.add(now, 120, :second))
    assert_receive {:countdown_tick, 120}

    Frozen.advance(20, :second)
    send(timer_pid(riddle_id), :tick)

    assert_receive {:countdown_tick, 100}
  end

  test "stops itself once the live date has passed", %{riddle_id: riddle_id, now: now} do
    :ok = LobbyTimer.ensure_started(riddle_id, DateTime.add(now, 30, :second))
    assert_receive {:countdown_tick, 30}

    pid = timer_pid(riddle_id)
    ref = Process.monitor(pid)

    Frozen.advance(31, :second)
    send(pid, :tick)

    assert_receive {:countdown_tick, 0}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  defp timer_pid(riddle_id) do
    [{pid, _}] = Registry.lookup(Riddlr.LobbyTimerRegistry, riddle_id)
    pid
  end
end
