defmodule Riddlr.Games.RiddleScheduler do
  @moduledoc """
  Handles scheduling and rescheduling of Oban jobs for riddle state transitions.

  This module provides utilities for:
  - Canceling all pending jobs for a riddle
  - Rescheduling jobs when a riddle's live_date changes
  """
  import Ecto.Query
  alias Ecto.Multi
  alias Riddlr.Games.Riddle
  alias Riddlr.Repo
  alias Riddlr.Workers.{ReadyRiddleTransitionWorker, LiveRiddleTransitionWorker}

  @transition_workers [
    "Riddlr.Workers.ReadyRiddleTransitionWorker",
    "Riddlr.Workers.LiveRiddleTransitionWorker",
    "Riddlr.Workers.ArchiveRiddleTransitionWorker",
    "Riddlr.Workers.CompleteRiddleWorker"
  ]

  @doc """
  Cancels all pending (scheduled or available) jobs for a riddle.

  Returns `{:ok, count}` where count is the number of cancelled jobs.

  ## Examples

      iex> cancel_pending_jobs(123)
      {:ok, 3}

      iex> cancel_pending_jobs(999)
      {:ok, 0}
  """
  def cancel_pending_jobs(riddle_id) when is_integer(riddle_id) do
    riddle_id_string = Integer.to_string(riddle_id)
    now = DateTime.utc_now()

    query =
      from j in Oban.Job,
        where: j.worker in ^@transition_workers,
        where: fragment("?->>'riddle_id' = ?", j.args, ^riddle_id_string),
        where: j.state in ["scheduled", "available"]

    {count, _jobs} =
      Repo.update_all(query,
        set: [state: "cancelled", cancelled_at: now]
      )

    {:ok, count}
  end

  @doc """
  Cancels existing jobs and schedules new ones based on updated live_date.

  Used when a riddle's live_date changes. This will:
  1. Cancel all pending jobs for the riddle
  2. Schedule new ReadyRiddleTransitionWorker (ready_before_seconds before live_date)
  3. Schedule new LiveRiddleTransitionWorker (at live_date)

  Returns `{:ok, count}` where count is the number of new jobs scheduled.

  ## Examples

      iex> reschedule_jobs(riddle, ~U[2026-04-01 14:00:00Z])
      {:ok, 2}
  """
  def reschedule_jobs(%Riddle{} = riddle, %DateTime{} = new_live_date) do
    riddle_ready_time = ready_time(new_live_date, riddle.ready_before_seconds)

    riddle_id_string = Integer.to_string(riddle.id)
    now = DateTime.utc_now()

    cancel_query =
      from j in Oban.Job,
        where: j.worker in ^@transition_workers,
        where: fragment("?->>'riddle_id' = ?", j.args, ^riddle_id_string),
        where: j.state in ["scheduled", "available"]

    case Multi.new()
         |> Multi.run(:cancel_jobs, fn repo, _changes ->
           {count, _} =
             repo.update_all(cancel_query, set: [state: "cancelled", cancelled_at: now])

           {:ok, count}
         end)
         |> Oban.insert(
           :ready_job,
           ReadyRiddleTransitionWorker.new(%{"riddle_id" => riddle.id},
             scheduled_at: riddle_ready_time
           )
         )
         |> Oban.insert(
           :live_job,
           LiveRiddleTransitionWorker.new(%{"riddle_id" => riddle.id},
             scheduled_at: new_live_date
           )
         )
         |> Repo.transaction() do
      {:ok, _changes} ->
        {:ok, 2}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _step, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  def reschedule_jobs(_riddle, _new_live_date), do: {:error, :invalid_live_date}

  defp ready_time(live_date, ready_before_seconds),
    do: DateTime.add(live_date, -ready_before_seconds, :second)
end
