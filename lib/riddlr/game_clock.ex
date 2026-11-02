defmodule Riddlr.GameClock do
  @moduledoc """
  A single countdown process per riddle, shared by everyone watching it.

  A riddle has two countdowns: the lobby counts down to the live date, and the
  play view counts down the solve time. Both are the same subtraction against
  the same live date, so one process runs both and broadcasts
  `{:countdown_tick, phase, seconds}` once per second on `topic/1`. Phase is
  `:lobby` before the live date and `:play` after it; subscribers handle the
  phase they care about and ignore the other.

  Without this, each LiveView ran its own one-second timer, so two players
  watching the same riddle saw the display change at different moments. One
  process ticking on wall-clock second boundaries means they change together.

  The process holds a snapshot of the riddle. It refreshes that snapshot when
  the riddle is saved, so rescheduling moves every connected countdown, and it
  exits when the solve time runs out or the riddle completes, is archived, or
  is deleted.

  It also batches the live guess feed (`push_answer/1`). Each guess sent to
  every viewer on its own costs guesses × viewers messages; held for
  `feed_flush_ms` and sent as one `{:answers_batch, answers, totals}`, it costs
  viewers messages per flush. The batch is display only: guesses live in
  `Riddlr.Gameplay.Store`, so a batch lost to a crash or to the riddle ending
  loses nothing a reload does not bring back.

  On each tick it also counts the Lobby and the solvers and, when either
  changed, broadcasts `{:riddle_stats, riddle_id, %{waiting: n, solved: m}}`
  on `stats_topic/1`. Home reads its counts from that instead of from every
  guess and every Lobby join.
  """

  # Transient: the clock stops with :normal when its riddle ends, and a
  # permanent child would be restarted to tick for a riddle that is over.
  use GenServer, restart: :transient

  alias Riddlr.Clock
  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Presence
  alias Riddlr.Gameplay.Store
  alias Riddlr.Games.Riddle

  @registry Riddlr.GameClockRegistry
  @supervisor Riddlr.GameClockSupervisor
  # The Play feed shows this many guesses; a batch never needs more.
  @feed_cap 100

  @typep state :: %{
           riddle: Riddle.t(),
           feed: [Answer.t()],
           flush_ref: reference() | nil,
           stats: stats() | nil
         }

  @typedoc "How many players wait in the Lobby and how many have solved."
  @type stats :: %{waiting: non_neg_integer(), solved: non_neg_integer()}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  The PubSub topic a riddle's ticks are broadcast on.
  """
  def topic(riddle_id), do: "game:clock:#{riddle_id}"

  @doc """
  The PubSub topic a riddle's Lobby and solver counts are broadcast on.
  """
  @spec stats_topic(integer()) :: String.t()
  def stats_topic(riddle_id), do: "game:stats:#{riddle_id}"

  @doc """
  The seconds left on a riddle's countdown right now.

  Returns `{:lobby, seconds}` before the live date and `{:play, seconds}` after
  it, where play seconds are what remains of the solve time. This is the only
  place the remaining-seconds arithmetic is written, so a LiveView's first
  render and the ticks that follow it always agree.

  A riddle with no live date has not been scheduled; it reports its full solve
  time.
  """
  def countdown(%Riddle{live_date: nil, solve_time: solve_time}), do: {:play, solve_time}

  def countdown(%Riddle{} = riddle) do
    case DateTime.diff(riddle.live_date, Clock.utc_now()) do
      until_live when until_live > 0 -> {:lobby, until_live}
      elapsed -> {:play, max(riddle.solve_time + elapsed, 0)}
    end
  end

  @doc """
  When a riddle is due to be archived: its live date plus its solve time plus
  its archive delay. The archive job counts its delay from when the riddle
  actually completes, so the two can drift by a second or so.

  A riddle with no live date has no archive time; returns `nil`.
  """
  @spec archive_at(Riddle.t()) :: DateTime.t() | nil
  def archive_at(%Riddle{live_date: nil}), do: nil

  def archive_at(%Riddle{} = riddle) do
    DateTime.add(riddle.live_date, riddle.solve_time + riddle.archive_after_seconds, :second)
  end

  def start_link(opts) do
    riddle = Keyword.fetch!(opts, :riddle)

    GenServer.start_link(__MODULE__, riddle, name: {:via, Registry, {@registry, riddle.id}})
  end

  @doc """
  Starts the clock for a riddle if it is not already running. Safe to call from
  many LiveView processes at once.

  Takes the riddle rather than an id so the registry key is always the integer
  `riddle.id`. A caller passing a string route param used to start a second
  clock for the same riddle.

  A riddle with no live date has nothing to count down to, so no clock starts.
  """
  def ensure_started(%Riddle{live_date: nil}), do: :ok

  def ensure_started(%Riddle{} = riddle) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, riddle: riddle}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      _ -> :ok
    end
  end

  @doc """
  Puts a stored guess on its riddle's live feed.

  The riddle's clock holds it until the next flush. With no clock running, or
  batching turned off in config, the guess goes out alone, at once.
  """
  @spec push_answer(Answer.t()) :: :ok
  def push_answer(%Answer{riddle_id: riddle_id} = answer) do
    case batch_feed?() && Registry.lookup(@registry, riddle_id) do
      [{pid, _}] -> send(pid, {:feed, answer})
      _no_clock -> Gameplay.broadcast_answers(riddle_id, [answer])
    end

    :ok
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────────

  @impl true
  def init(%Riddle{} = riddle) do
    # The riddle is held as a snapshot, so the clock subscribes to the writes
    # that change what it counts down to, and to the transitions that end the
    # riddle before its solve time runs out.
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:changed")
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")

    schedule_tick()
    broadcast(riddle)
    {:ok, %{riddle: riddle, feed: [], flush_ref: nil, stats: nil}}
  end

  # A batch still held when the clock stops is dropped: viewers are leaving
  # for Results, which reads the guesses from the Store.
  @impl true
  @spec handle_info(term(), state()) :: {:noreply, state()} | {:stop, :normal, state()}
  def handle_info(:tick, state) do
    case broadcast(state.riddle) do
      {:play, 0} ->
        {:stop, :normal, state}

      _still_counting ->
        schedule_tick()
        {:noreply, broadcast_stats(state)}
    end
  end

  # The first guess after a flush starts the timer, so an idle riddle runs none.
  def handle_info({:feed, answer}, %{flush_ref: nil} = state) do
    ref = Process.send_after(self(), :flush_feed, flush_ms())
    {:noreply, %{state | feed: [answer], flush_ref: ref}}
  end

  def handle_info({:feed, answer}, state) do
    {:noreply, %{state | feed: [answer | state.feed]}}
  end

  def handle_info(:flush_feed, %{feed: []} = state), do: {:noreply, %{state | flush_ref: nil}}

  def handle_info(:flush_feed, state) do
    answers = state.feed |> Enum.take(@feed_cap) |> Enum.reverse()
    Gameplay.broadcast_answers(state.riddle.id, answers)
    {:noreply, %{state | feed: [], flush_ref: nil}}
  end

  def handle_info({:riddle_saved, %Riddle{id: id} = saved}, %{riddle: %Riddle{id: id}} = state) do
    {:noreply, %{state | riddle: saved}}
  end

  def handle_info({event, %Riddle{id: id}}, %{riddle: %Riddle{id: id}} = state)
      when event in [:riddle_completed, :riddle_archived, :riddle_deleted] do
    {:stop, :normal, state}
  end

  # Broadcasts about other riddles, which both topics carry.
  def handle_info(_message, state), do: {:noreply, state}

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp broadcast_stats(%{riddle: %{id: id}} = state) do
    stats = %{
      waiting: id |> Presence.lobby_topic() |> Presence.list() |> map_size(),
      solved: Store.solved_count(id)
    }

    if stats != state.stats do
      Phoenix.PubSub.broadcast(Riddlr.PubSub, stats_topic(id), {:riddle_stats, id, stats})
    end

    %{state | stats: stats}
  end

  defp batch_feed?, do: config(:batch_feed, true)
  defp flush_ms, do: config(:feed_flush_ms, 250)

  defp config(key, default) do
    :riddlr |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
  end

  defp broadcast(riddle) do
    {phase, seconds} = countdown(riddle)

    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      topic(riddle.id),
      {:countdown_tick, phase, seconds}
    )

    {phase, seconds}
  end

  # Align to the next wall-clock second boundary to prevent timer drift.
  defp schedule_tick do
    ms = 1000 - rem(DateTime.to_unix(Clock.utc_now(), :millisecond), 1000)
    Process.send_after(self(), :tick, ms)
  end
end
