defmodule Riddlr.LobbyTimer do
  @moduledoc """
  Per-riddle GenServer that broadcasts a synchronized countdown tick to all
  lobby subscribers once per second.

  A single process serves all connected players for a given riddle, replacing
  the per-user `send_interval` timers that caused each browser to update at a
  different phase. All LiveViews receive the same `{:countdown_tick, seconds}`
  message simultaneously via PubSub.

  Ticks are aligned to wall-clock second boundaries to prevent drift.
  The process stops itself when `time_remaining` reaches zero.
  """

  use GenServer

  alias Riddlr.Clock

  @registry Riddlr.LobbyTimerRegistry
  @supervisor Riddlr.LobbyTimerSupervisor

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(opts) do
    riddle_id = Keyword.fetch!(opts, :riddle_id)
    live_date = Keyword.fetch!(opts, :live_date)

    GenServer.start_link(__MODULE__, {riddle_id, live_date},
      name: {:via, Registry, {@registry, riddle_id}}
    )
  end

  @doc """
  Ensures a timer is running for the given riddle. Safe to call from multiple
  LiveView processes concurrently — handles the already-started race gracefully.
  """
  def ensure_started(riddle_id, live_date) do
    case DynamicSupervisor.start_child(
           @supervisor,
           {__MODULE__, riddle_id: riddle_id, live_date: live_date}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      _ -> :ok
    end
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────────

  @impl true
  def init({riddle_id, live_date} = state) do
    schedule_tick()
    broadcast(riddle_id, live_date)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, {riddle_id, live_date} = state) do
    seconds = broadcast(riddle_id, live_date)

    if seconds > 0 do
      schedule_tick()
      {:noreply, state}
    else
      {:stop, :normal, state}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp broadcast(riddle_id, live_date) do
    seconds = max(0, DateTime.diff(live_date, Clock.utc_now()))

    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "game:lobby:#{riddle_id}",
      {:countdown_tick, seconds}
    )

    seconds
  end

  # Align to the next wall-clock second boundary to prevent timer drift.
  defp schedule_tick do
    ms = 1000 - rem(DateTime.to_unix(Clock.utc_now(), :millisecond), 1000)
    Process.send_after(self(), :tick, ms)
  end
end
