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
  """

  use GenServer

  alias Riddlr.Clock
  alias Riddlr.Games.Riddle

  @registry Riddlr.GameClockRegistry
  @supervisor Riddlr.GameClockSupervisor

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  The PubSub topic a riddle's ticks are broadcast on.
  """
  def topic(riddle_id), do: "game:clock:#{riddle_id}"

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
    {:ok, riddle}
  end

  @impl true
  def handle_info(:tick, riddle) do
    case broadcast(riddle) do
      {:play, 0} ->
        {:stop, :normal, riddle}

      _still_counting ->
        schedule_tick()
        {:noreply, riddle}
    end
  end

  def handle_info({:riddle_saved, %Riddle{id: id} = saved}, %Riddle{id: id}) do
    {:noreply, saved}
  end

  def handle_info({event, %Riddle{id: id}}, %Riddle{id: id} = riddle)
      when event in [:riddle_completed, :riddle_archived, :riddle_deleted] do
    {:stop, :normal, riddle}
  end

  # Broadcasts about other riddles, which both topics carry.
  def handle_info(_message, riddle), do: {:noreply, riddle}

  # ── Helpers ──────────────────────────────────────────────────────────────────

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
