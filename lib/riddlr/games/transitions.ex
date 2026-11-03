defmodule Riddlr.Games.Transitions do
  @moduledoc """
  Moves a riddle through its play statuses: scheduled, ready, live,
  completed, archived.

  `Riddlr.Games.transition/3` delegates here. Each move writes the status,
  queues the job for the next move, and broadcasts after the commit.
  """

  alias Ecto.Multi
  alias Riddlr.Games
  alias Riddlr.Games.Riddle
  alias Riddlr.Repo

  alias Riddlr.Workers.{
    ArchiveRiddleTransitionWorker,
    CompleteRiddleWorker,
    NotificationFanOutWorker
  }

  @type status :: :ready | :live | :completed | :archived

  @type result ::
          {:ok, Riddle.t()}
          | {:error, :not_found | Ecto.Changeset.t()}
          | {:unpublished, String.t()}
          | {:invalid, String.t(), status()}

  @doc """
  Transitions a riddle's play status.

  One interface for every Play status transition: it owns the guards, the write,
  the follow-on job, the broadcast and any cleanup. Callers (Oban workers,
  Gameplay) supply only the target status and, for `:completed`, stats.

  For `:completed`, `stats` also carries the `:solves` and `:entries` rows.
  `Riddlr.Gameplay.persist_results/3` saves them in the same transaction as
  the status change.

  Returns:

    * `{:ok, riddle}` — transitioned and committed
    * `{:error, :not_found}` — no such riddle
    * `{:unpublished, publish_status}` — riddle is not published
    * `{:invalid, from, to}` — forbidden by `Riddle.valid_transitions/0`
    * `{:error, changeset}` — the write failed

  The three non-changeset failures are permanent: callers should not retry.
  """
  @spec transition(integer(), status(), map()) :: result()
  def transition(riddle_id, to, stats \\ %{}) do
    with {:ok, riddle} <- fetch_transitionable(riddle_id, to) do
      riddle
      |> run_transition(to, stats)
      |> after_commit(to)
    end
  end

  @spec fetch_transitionable(integer(), status()) ::
          {:ok, Riddle.t()}
          | {:error, :not_found}
          | {:unpublished, String.t()}
          | {:invalid, String.t(), status()}
  defp fetch_transitionable(riddle_id, to) do
    case Repo.get(Riddle, riddle_id) do
      nil ->
        {:error, :not_found}

      %Riddle{publish_status: publish_status} when publish_status != "published" ->
        {:unpublished, publish_status}

      riddle ->
        if Riddle.can_transition?(riddle.play_status, to) do
          {:ok, riddle}
        else
          {:invalid, riddle.play_status, to}
        end
    end
  end

  @spec run_transition(Riddle.t(), status(), map()) ::
          {:ok, Riddle.t()} | {:error, Ecto.Changeset.t()}
  defp run_transition(riddle, to, stats) do
    Multi.new()
    |> Multi.update(:riddle, Riddle.changeset(riddle, transition_attrs(to, stats)))
    |> save_results(to, stats)
    |> enqueue_next_job(to)
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: riddle}} -> {:ok, riddle}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
  end

  # The solves and entries go in with the move to `completed`, so the board,
  # the solve rate and the status commit or roll back as one. A retry after
  # rollback writes them again; a second run after commit is refused as an
  # invalid transition.
  @spec save_results(Multi.t(), status(), map()) :: Multi.t()
  defp save_results(multi, :completed, stats),
    do: Riddlr.Gameplay.persist_results(multi, stats)

  defp save_results(multi, _to, _stats), do: multi

  @spec enqueue_next_job(Multi.t(), status()) :: Multi.t()
  defp enqueue_next_job(multi, :ready) do
    Multi.insert(multi, :fan_out_job, fn %{riddle: riddle} ->
      NotificationFanOutWorker.new(%{
        "riddle_id" => riddle.id,
        "lead_time" => "lobby_open"
      })
    end)
  end

  defp enqueue_next_job(multi, :live) do
    Multi.insert(multi, :complete_job, fn %{riddle: riddle} ->
      %{"riddle_id" => riddle.id}
      |> CompleteRiddleWorker.new(schedule_in: riddle.solve_time)
    end)
  end

  defp enqueue_next_job(multi, :completed) do
    Multi.insert(multi, :archive_job, fn %{riddle: riddle} ->
      %{"riddle_id" => riddle.id}
      |> ArchiveRiddleTransitionWorker.new(schedule_in: riddle.archive_after_seconds)
    end)
  end

  defp enqueue_next_job(multi, _to), do: multi

  @spec transition_attrs(status(), map()) :: map()
  defp transition_attrs(:completed, stats) do
    stats
    |> Map.take([:first_solver_id, :first_solve_time, :completion_rate])
    |> Map.put(:play_status, "completed")
  end

  defp transition_attrs(to, _stats), do: %{play_status: to_string(to)}

  # Everything that must not happen until the transaction has committed:
  # broadcasting a rolled-back transition would move every Lobby to a riddle
  # that never went live.
  @spec after_commit(result(), status()) :: result()
  defp after_commit({:ok, riddle}, to) do
    cleanup(to, riddle)
    # Every Play view moves to Results on the broadcast below, so the board
    # must be cached first.
    if to == :completed, do: Riddlr.Gameplay.warm_board(riddle.id)
    Games.refresh_home()

    broadcast_riddle = Games.preload_riddle(riddle)
    {topic, message} = broadcast_for(to)

    Phoenix.PubSub.broadcast(Riddlr.PubSub, topic, {message, broadcast_riddle})
    if to == :completed, do: Riddlr.Standings.broadcast_changed()

    {:ok, riddle}
  end

  defp after_commit(other, _to), do: other

  # An archived riddle takes no more answers, so its ETS rows are dead weight.
  @spec cleanup(status(), Riddle.t()) :: :ok
  defp cleanup(:archived, riddle), do: Riddlr.Gameplay.cleanup_riddle(riddle.id)
  defp cleanup(_to, _riddle), do: :ok

  @spec broadcast_for(status()) :: {String.t(), atom()}
  defp broadcast_for(:ready), do: {"games:riddle:ready", :riddle_ready}
  defp broadcast_for(:live), do: {"games:riddle:live", :riddle_live}
  defp broadcast_for(:completed), do: {"games:riddle:completed", :riddle_completed}
  defp broadcast_for(:archived), do: {"games:riddle:archived", :riddle_archived}
end
