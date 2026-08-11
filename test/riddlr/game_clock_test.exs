defmodule Riddlr.GameClockTest do
  # Freezes the clock — must not run alongside other clock readers.
  use ExUnit.Case, async: false

  alias Riddlr.Clock.Frozen
  alias Riddlr.GameClock
  alias Riddlr.Games.Riddle

  setup do
    riddle_id = :erlang.unique_integer([:positive])
    now = ~U[2026-08-01 12:00:00.000000Z]
    Frozen.freeze(now)
    Phoenix.PubSub.subscribe(Riddlr.PubSub, GameClock.topic(riddle_id))

    %{riddle_id: riddle_id, now: now}
  end

  describe "lobby phase" do
    test "broadcasts the seconds until the live date as soon as it starts", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 120))

      assert_receive {:countdown_tick, :lobby, 120}
    end

    test "each tick broadcasts the seconds left on the frozen clock", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 120))
      assert_receive {:countdown_tick, :lobby, 120}

      Frozen.advance(20, :second)
      send(clock_pid(ctx.riddle_id), :tick)

      assert_receive {:countdown_tick, :lobby, 100}
    end
  end

  describe "play phase" do
    test "counts the solve time down once the live date has passed", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10, solve_time: 60))
      assert_receive {:countdown_tick, :lobby, 10}

      Frozen.advance(25, :second)
      send(clock_pid(ctx.riddle_id), :tick)

      assert_receive {:countdown_tick, :play, 45}
    end

    test "rolls from the lobby countdown into the solve countdown", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 1, solve_time: 60))
      assert_receive {:countdown_tick, :lobby, 1}

      Frozen.advance(1, :second)
      send(clock_pid(ctx.riddle_id), :tick)

      assert_receive {:countdown_tick, :play, 60}
      assert Process.alive?(clock_pid(ctx.riddle_id))
    end

    test "stops itself once the solve time has run out", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10, solve_time: 60))
      assert_receive {:countdown_tick, :lobby, 10}

      pid = clock_pid(ctx.riddle_id)
      ref = Process.monitor(pid)

      Frozen.advance(71, :second)
      send(pid, :tick)

      assert_receive {:countdown_tick, :play, 0}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  describe "keeping up with the riddle" do
    test "counts to the new live date after a reschedule", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10))
      assert_receive {:countdown_tick, :lobby, 10}

      broadcast("games:riddle:changed", {:riddle_saved, riddle(ctx, live_in: 300)})

      send(clock_pid(ctx.riddle_id), :tick)

      assert_receive {:countdown_tick, :lobby, 300}
    end

    test "ignores a save for a different riddle", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10))
      assert_receive {:countdown_tick, :lobby, 10}

      other = %{riddle(ctx, live_in: 300) | id: ctx.riddle_id + 1}
      broadcast("games:riddle:changed", {:riddle_saved, other})

      send(clock_pid(ctx.riddle_id), :tick)

      assert_receive {:countdown_tick, :lobby, 10}
    end

    test "a lobby that outlives its live date keeps ticking, it does not freeze", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10))
      assert_receive {:countdown_tick, :lobby, 10}

      pid = clock_pid(ctx.riddle_id)
      Frozen.advance(11, :second)
      send(pid, :tick)
      assert_receive {:countdown_tick, :play, 59}

      broadcast("games:riddle:changed", {:riddle_saved, riddle(ctx, live_in: 400)})
      send(pid, :tick)

      assert_receive {:countdown_tick, :lobby, 389}
    end

    for {topic, message} <- [
          {"games:riddle:completed", :riddle_completed},
          {"games:riddle:archived", :riddle_archived},
          {"games:riddle:changed", :riddle_deleted}
        ] do
      test "stops on #{message}", ctx do
        :ok = GameClock.ensure_started(riddle(ctx, live_in: 10))
        assert_receive {:countdown_tick, :lobby, 10}

        pid = clock_pid(ctx.riddle_id)
        ref = Process.monitor(pid)

        broadcast(unquote(topic), {unquote(message), riddle(ctx, live_in: 10)})

        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      end
    end
  end

  test "a riddle with no live date has nothing to count", ctx do
    :ok = GameClock.ensure_started(%Riddle{id: ctx.riddle_id, live_date: nil, solve_time: 60})

    assert Registry.lookup(Riddlr.GameClockRegistry, ctx.riddle_id) == []
    refute_receive {:countdown_tick, _, _}
  end

  test "starts at most one clock per riddle", ctx do
    riddle = riddle(ctx, live_in: 120)

    :ok = GameClock.ensure_started(riddle)
    :ok = GameClock.ensure_started(riddle)

    assert [_only_one] = Registry.lookup(Riddlr.GameClockRegistry, ctx.riddle_id)
  end

  defp riddle(ctx, opts) do
    %Riddle{
      id: ctx.riddle_id,
      live_date: DateTime.add(ctx.now, Keyword.fetch!(opts, :live_in), :second),
      solve_time: Keyword.get(opts, :solve_time, 60)
    }
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Riddlr.PubSub, topic, message)
    # Give the clock time to process the broadcast before the :tick sent next.
    # A GenServer.call would be more precise, but the clock exposes none.
    Process.sleep(10)
  end

  defp clock_pid(riddle_id) do
    [{pid, _}] = Registry.lookup(Riddlr.GameClockRegistry, riddle_id)
    pid
  end
end
