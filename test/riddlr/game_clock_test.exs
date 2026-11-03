defmodule Riddlr.GameClockTest do
  # Freezes the clock — must not run alongside other clock readers.
  use ExUnit.Case, async: false

  alias Riddlr.Clock.Frozen
  alias Riddlr.GameClock
  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Store
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

      pid = clock_pid(ctx.riddle_id)
      ref = Process.monitor(pid)

      Frozen.advance(1, :second)
      send(pid, :tick)

      assert_receive {:countdown_tick, :play, 60}
      _ = :sys.get_state(pid)
      refute_received {:DOWN, ^ref, :process, ^pid, _}
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
      refute_restarted(ctx.riddle_id, pid)
    end
  end

  describe "archive_at/1" do
    test "is the live date plus the solve time plus the archive delay", ctx do
      riddle = %{riddle(ctx, live_in: 10, solve_time: 60) | archive_after_seconds: 180}

      assert GameClock.archive_at(riddle) == DateTime.add(ctx.now, 250, :second)
    end

    test "is nil for a riddle with no live date" do
      assert GameClock.archive_at(%Riddle{live_date: nil, solve_time: 60}) == nil
    end
  end

  describe "keeping up with the riddle" do
    test "counts to the new live date after a reschedule", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10))
      assert_receive {:countdown_tick, :lobby, 10}

      pid = clock_pid(ctx.riddle_id)
      broadcast("games:riddle:changed", {:riddle_saved, riddle(ctx, live_in: 300)}, pid)

      send(pid, :tick)

      assert_receive {:countdown_tick, :lobby, 300}
    end

    test "ignores a save for a different riddle", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10))
      assert_receive {:countdown_tick, :lobby, 10}

      other = %{riddle(ctx, live_in: 300) | id: ctx.riddle_id + 1}
      pid = clock_pid(ctx.riddle_id)
      broadcast("games:riddle:changed", {:riddle_saved, other}, pid)

      send(pid, :tick)

      assert_receive {:countdown_tick, :lobby, 10}
    end

    test "a lobby that outlives its live date keeps ticking, it does not freeze", ctx do
      :ok = GameClock.ensure_started(riddle(ctx, live_in: 10))
      assert_receive {:countdown_tick, :lobby, 10}

      pid = clock_pid(ctx.riddle_id)
      Frozen.advance(11, :second)
      send(pid, :tick)
      assert_receive {:countdown_tick, :play, 59}

      broadcast("games:riddle:changed", {:riddle_saved, riddle(ctx, live_in: 400)}, pid)
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

        Phoenix.PubSub.broadcast(
          Riddlr.PubSub,
          unquote(topic),
          {unquote(message), riddle(ctx, live_in: 10)}
        )

        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
        refute_restarted(ctx.riddle_id, pid)
      end
    end
  end

  describe "stats" do
    test "sends Lobby and solver counts on a tick, only when they change", ctx do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, GameClock.stats_topic(ctx.riddle_id))
      on_exit(fn -> Store.cleanup_riddle(ctx.riddle_id) end)
      :ok = GameClock.ensure_started(riddle(ctx, live_in: -5, solve_time: 600))
      pid = clock_pid(ctx.riddle_id)

      send(pid, :tick)
      assert_receive {:riddle_stats, id, %{waiting: 0, solved: 0}} when id == ctx.riddle_id

      send(pid, :tick)
      refute_receive {:riddle_stats, _, _}

      user = %{id: 1, username: "u1"}
      {:ok, 1} = Store.record(Answer.new(ctx.riddle_id, user, "x", correct: true))
      send(pid, :tick)
      assert_receive {:riddle_stats, _, %{waiting: 0, solved: 1}}
    end
  end

  describe "feed batching" do
    setup ctx do
      config = Application.get_env(:riddlr, GameClock)
      # A long interval, so only the test's own :flush_feed sends a batch.
      Application.put_env(:riddlr, GameClock, batch_feed: true, feed_flush_ms: 60_000)
      on_exit(fn -> Application.put_env(:riddlr, GameClock, config) end)
      on_exit(fn -> Store.cleanup_riddle(ctx.riddle_id) end)

      :ok = GameClock.ensure_started(riddle(ctx, live_in: -5, solve_time: 600))
      %{clock: clock_pid(ctx.riddle_id)}
    end

    for viewers <- [5, 200] do
      test "sends #{viewers} viewers one message per flush, however many guesses", ctx do
        viewers = Enum.map(1..unquote(viewers), fn _ -> viewer(ctx.riddle_id) end)

        for _ <- 1..50, do: guess(ctx.riddle_id)
        _ = :sys.get_state(ctx.clock)
        assert Enum.all?(viewers, &(received(&1) == []))

        send(ctx.clock, :flush_feed)
        _ = :sys.get_state(ctx.clock)

        for viewer <- viewers do
          assert [{:answers_batch, answers, %{guesses: 50, solved: 0}}] = received(viewer)
          assert length(answers) == 50
          assert answers == Enum.sort_by(answers, & &1.timestamp)
        end
      end
    end

    test "masks correct answers in the batch", ctx do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(ctx.riddle_id))
      guess(ctx.riddle_id, correct: true)

      send(ctx.clock, :flush_feed)

      assert_receive {:answers_batch, [%Answer{correct: true, text: nil}], %{solved: 1}}
    end

    test "with no clock running, a guess goes out alone at once" do
      riddle_id = :erlang.unique_integer([:positive])
      Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(riddle_id))

      guess(riddle_id)

      assert_receive {:answers_batch, [%Answer{}], %{guesses: 1}}
      Store.cleanup_riddle(riddle_id)
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

  defp guess(riddle_id, opts \\ []) do
    id = :erlang.unique_integer([:positive])
    answer = Answer.new(riddle_id, %{id: id, username: "u#{id}"}, "guess", opts)
    {:ok, placement} = Store.record(answer)
    GameClock.push_answer(%{answer | placement: placement})
  end

  # A process standing in for a viewer's LiveView: it subscribes to the
  # riddle's feed and hands back what it has received when asked.
  defp viewer(riddle_id) do
    test = self()

    pid =
      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(riddle_id))
        send(test, {:subscribed, self()})
        collect([])
      end)

    assert_receive {:subscribed, ^pid}
    pid
  end

  defp collect(messages) do
    receive do
      {:report, from} ->
        send(from, {:received, self(), Enum.reverse(messages)})
        collect([])

      message ->
        collect([message | messages])
    end
  end

  defp received(viewer) do
    send(viewer, {:report, self()})
    assert_receive {:received, ^viewer, messages}
    messages
  end

  defp riddle(ctx, opts) do
    %Riddle{
      id: ctx.riddle_id,
      live_date: DateTime.add(ctx.now, Keyword.fetch!(opts, :live_in), :second),
      solve_time: Keyword.get(opts, :solve_time, 60)
    }
  end

  # Returns once the clock has handled the broadcast, so the :tick sent next
  # sees the change.
  defp broadcast(topic, message, clock) do
    Phoenix.PubSub.broadcast(Riddlr.PubSub, topic, message)
    _ = :sys.get_state(clock)
  end

  # A clock that stops on purpose must stay stopped. The supervisor handles the
  # exit before this call returns, so a restarted clock is registered by then.
  # The Registry drops a dead process's entry on its own time, so the stopped
  # clock may still be listed; only a different pid means a restart.
  defp refute_restarted(riddle_id, stopped) do
    _ = :sys.get_state(Riddlr.GameClockSupervisor)

    assert Registry.lookup(Riddlr.GameClockRegistry, riddle_id) in [[], [{stopped, nil}]]
  end

  defp clock_pid(riddle_id) do
    [{pid, _}] = Registry.lookup(Riddlr.GameClockRegistry, riddle_id)
    pid
  end
end
