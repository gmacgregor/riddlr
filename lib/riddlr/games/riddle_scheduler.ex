defmodule Riddlr.Games.RiddleScheduler do
  @moduledoc """
  Handles scheduling and rescheduling of Oban jobs for riddle state transitions.

  This module provides utilities for:
  - Canceling all pending jobs for a riddle
  - Rescheduling jobs when a riddle's live_date changes
  """
  import Ecto.Query
  alias Ecto.Multi
  alias Riddlr.Repo
  alias Riddlr.Workers.{ReadyRiddleTransitionWorker, LiveRiddleTransitionWorker}

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
    riddle_id_string = to_string(riddle_id)

    {count, _} =
      Oban.Job
      |> where(
        [j],
        j.worker in [
          "Riddlr.Workers.ReadyRiddleTransitionWorker",
          "Riddlr.Workers.LiveRiddleTransitionWorker",
          "Riddlr.Workers.ArchiveRiddleTransitionWorker"
        ]
      )
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^riddle_id_string))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])

    {:ok, count}
  end

  @doc """
  Cancels existing jobs and schedules new ones based on updated live_date.

  Used when a riddle's live_date changes. This will:
  1. Cancel all pending jobs for the riddle
  2. Schedule new ReadyRiddleTransitionWorker (5 min before live_date)
  3. Schedule new LiveRiddleTransitionWorker (at live_date)

  Returns `{:ok, count}` where count is the number of new jobs scheduled.

  ## Examples

      iex> reschedule_jobs(123, ~U[2026-04-01 14:00:00Z])
      {:ok, 2}
  """
  def reschedule_jobs(riddle_id, new_live_date) when is_integer(riddle_id) do
    # Cancel existing jobs
    {:ok, _cancelled} = cancel_pending_jobs(riddle_id)

    # Schedule new jobs
    ready_time = DateTime.add(new_live_date, -300, :second)

    Multi.new()
    |> Multi.insert(
      :ready_job,
      ReadyRiddleTransitionWorker.new(
        %{riddle_id: riddle_id},
        scheduled_at: ready_time
      )
    )
    |> Multi.insert(
      :live_job,
      LiveRiddleTransitionWorker.new(
        %{riddle_id: riddle_id},
        scheduled_at: new_live_date
      )
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, 2}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end
end
