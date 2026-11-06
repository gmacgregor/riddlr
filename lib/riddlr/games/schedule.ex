defmodule Riddlr.Games.Schedule do
  @moduledoc """
  Writes and deletes riddles with their Oban jobs. A save decides whether it
  also schedules, reschedules or unschedules the riddle, and writes the row
  and the jobs in one transaction.

  `Riddlr.Games.save_riddle/3` and `delete_riddle/2` check the caller's scope,
  then call here.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Riddlr.Clock
  alias Riddlr.Games
  alias Riddlr.Games.Riddle
  alias Riddlr.Games.RiddleSeason
  alias Riddlr.Notifications
  alias Riddlr.Repo

  alias Riddlr.Workers.{
    ArchiveRiddleTransitionWorker,
    CompleteRiddleWorker,
    LiveRiddleTransitionWorker,
    NotificationFanOutWorker,
    ReadyRiddleTransitionWorker
  }

  # The four workers that take a riddle_id argument. Cancelling a riddle's
  # pending work means cancelling jobs from this list, which is why it exists as
  # one list rather than a filter written out at each call site.
  #
  # Stored as strings because Oban's `worker` column holds the module name
  # without the `Elixir.` prefix — which is what `inspect/1` produces and
  # `to_string/1` does not. A function, not a module attribute: naming the
  # workers in the module body makes them compile-time dependencies, which
  # ties Games and every worker into one recompile cycle.
  @spec riddle_workers() :: [String.t()]
  defp riddle_workers do
    Enum.map(
      [
        ReadyRiddleTransitionWorker,
        LiveRiddleTransitionWorker,
        ArchiveRiddleTransitionWorker,
        CompleteRiddleWorker
      ],
      &inspect/1
    )
  end

  # Unschedule and delete also drop every pending Notification fan-out: the
  # riddle will not go live, so no one should hear that it will. Schedule and
  # Reschedule replace only the 30 min and 1 hour fan-outs (see
  # `Notifications.replace_timed_fan_outs/2`); a pending Lobby-open fan-out
  # stays, and the send job reads the new Live date.
  @spec drop_workers() :: [String.t()]
  defp drop_workers, do: [inspect(NotificationFanOutWorker) | riddle_workers()]

  # A job in any other state has already run, been cancelled or been discarded,
  # so there is nothing left to cancel.
  @cancellable_states ["available", "scheduled", "retryable"]

  @doc """
  Writes a riddle and, inside the same transaction, the Oban jobs its
  schedule needs. See `Riddlr.Games.save_riddle/3` for the four intents.
  """
  @spec save(Riddle.t(), map()) :: {:ok, Riddle.t()} | {:error, Ecto.Changeset.t()}
  def save(%Riddle{} = riddle, attrs) do
    changeset = riddle |> Riddle.changeset(attrs) |> RiddleSeason.resolve(Clock.utc_now())

    # An invalid changeset gets `:none`: the transaction will roll back anyway,
    # and skipping the intent avoids running the validations twice and doubling
    # every error message in the form.
    intent = if changeset.valid?, do: intent(riddle, changeset), else: :none

    Multi.new()
    |> Multi.insert_or_update(:riddle, apply_intent(changeset, intent))
    |> write_jobs(intent)
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: saved}} ->
        {:ok, saved |> Games.preload_riddle(force: true) |> announce(intent)}

      {:error, _failed_operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @typep intent :: :schedule | :reschedule | :unschedule | :none
  @typep schedule_event :: :riddle_scheduled | :riddle_rescheduled | :riddle_unscheduled

  # Decides whether a save also changes the schedule: given the riddle as it is
  # stored and the changes the admin just submitted, which of the four intents
  # applies?
  #
  # Clause order is part of the rule, not an implementation detail:
  #
  #   1. Un-publishing wins over everything. A draft riddle with pending jobs is
  #      the one state that must never survive a save.
  #   2. A draft riddle is never scheduled, so nothing else can apply.
  #   3. No Live date, no schedule — the jobs have nothing to hang off.
  #   4. From `closed` this is a first schedule, and only a *future* Live date
  #      earns one. A past date is the admin filling in a form, not asking for a
  #      game that already started.
  #   5. From `scheduled`/`ready` the jobs already exist, so the question is only
  #      whether they still match the row. A past date *does* reschedule here:
  #      the admin is moving a game they already scheduled, and Oban running the
  #      job immediately is the honest result.
  #
  # Anything that falls through is `:none` — a riddle that cannot be scheduled is
  # not an error, it is simply not a schedule, and the row is written regardless.
  # That is what lets `save_riddle/3` return one error shape.
  @spec intent(Riddle.t(), Ecto.Changeset.t()) :: intent()
  defp intent(%Riddle{} = riddle, changeset) do
    live_date = Ecto.Changeset.get_field(changeset, :live_date)

    cond do
      unscheduling?(riddle, changeset) ->
        :unschedule

      Ecto.Changeset.get_field(changeset, :publish_status) != "published" ->
        :none

      is_nil(live_date) ->
        :none

      riddle.play_status == "closed" ->
        if DateTime.compare(live_date, Clock.utc_now()) == :lt, do: :none, else: :schedule

      riddle.play_status in ["scheduled", "ready"] and schedule_moved?(changeset) ->
        :reschedule

      true ->
        :none
    end
  end

  # Rolling back to draft is the only way to un-schedule: the pending jobs would
  # otherwise take an unpublished riddle live.
  @spec unscheduling?(Riddle.t(), Ecto.Changeset.t()) :: boolean()
  defp unscheduling?(%Riddle{play_status: play_status}, changeset)
       when play_status in ["scheduled", "ready"],
       do: Ecto.Changeset.get_field(changeset, :publish_status) != "published"

  defp unscheduling?(_riddle, _changeset), do: false

  # The two fields the pending jobs are derived from — `live_date` sets the live
  # job and, minus the lead time, the ready job. Either one moving means the jobs
  # on disk no longer match the row, so both are rewritten.
  @spec schedule_moved?(Ecto.Changeset.t()) :: boolean()
  defp schedule_moved?(changeset) do
    Enum.any?([:live_date, :ready_before_seconds], fn field ->
      not is_nil(Ecto.Changeset.get_change(changeset, field))
    end)
  end

  # The intent is also a Play status change. Re-running `Riddle.changeset/2` over
  # the changeset (rather than `put_change/3`) keeps the transition table in
  # `Riddle` the only judge of whether the move is legal.
  @spec apply_intent(Ecto.Changeset.t(), intent()) :: Ecto.Changeset.t()
  defp apply_intent(changeset, :schedule),
    do: Riddle.changeset(changeset, %{play_status: "scheduled"})

  defp apply_intent(changeset, :unschedule),
    do: Riddle.changeset(changeset, %{play_status: "closed"})

  defp apply_intent(changeset, _intent), do: changeset

  @spec write_jobs(Multi.t(), intent()) :: Multi.t()
  defp write_jobs(multi, intent) when intent in [:schedule, :reschedule] do
    multi
    |> Multi.run(:cancel_jobs, fn repo, %{riddle: riddle} ->
      cancel_jobs(repo, riddle.id, riddle_workers())
    end)
    |> Multi.insert(:ready_job, fn %{riddle: riddle} ->
      ReadyRiddleTransitionWorker.new(%{"riddle_id" => riddle.id},
        scheduled_at: DateTime.add(riddle.live_date, -riddle.ready_before_seconds, :second)
      )
    end)
    |> Multi.insert(:live_job, fn %{riddle: riddle} ->
      LiveRiddleTransitionWorker.new(%{"riddle_id" => riddle.id},
        scheduled_at: riddle.live_date
      )
    end)
    |> Multi.run(:timed_fan_out_jobs, fn repo, %{riddle: riddle} ->
      Notifications.replace_timed_fan_outs(repo, riddle)
    end)
  end

  defp write_jobs(multi, :unschedule) do
    multi
    |> Multi.run(:cancel_jobs, fn repo, %{riddle: riddle} ->
      cancel_jobs(repo, riddle.id, drop_workers())
    end)
    |> Multi.run(:drop_notifications, fn repo, %{riddle: riddle} ->
      Notifications.drop_unsent(repo, riddle.id)
    end)
  end

  defp write_jobs(multi, :none), do: multi

  # Broadcasts run after COMMIT, never inside the transaction: announcing a
  # schedule that then rolled back would leave every subscriber with a riddle
  # that is not actually scheduled.
  #
  # Two topics, two audiences. `games:riddle:changed` says a riddle row was
  # written or removed, whatever the reason — that is what the admin index needs
  # to re-render. `games:riddle:scheduled` reports what happened to the schedule
  # itself — a riddle is now upcoming, its start time moved, or it is no longer
  # upcoming — which is what a homepage listing or a player notification needs.
  @spec announce(Riddle.t(), intent()) :: Riddle.t()
  defp announce(riddle, intent) do
    Games.refresh_home()

    Phoenix.PubSub.broadcast(Riddlr.PubSub, "games:riddle:changed", {:riddle_saved, riddle})

    case schedule_event(intent) do
      nil -> :ok
      message -> broadcast_schedule_event(message, riddle)
    end

    riddle
  end

  @spec broadcast_schedule_event(schedule_event(), Riddle.t()) :: :ok | {:error, term()}
  defp broadcast_schedule_event(message, riddle) do
    Phoenix.PubSub.broadcast(Riddlr.PubSub, "games:riddle:scheduled", {message, riddle})
  end

  @spec schedule_event(intent()) :: schedule_event() | nil
  defp schedule_event(:schedule), do: :riddle_scheduled
  defp schedule_event(:reschedule), do: :riddle_rescheduled
  defp schedule_event(:unschedule), do: :riddle_unscheduled
  defp schedule_event(_intent), do: nil

  # The one place that cancels a riddle's jobs. Callers pass the worker list they
  # want cancelled, and the repo, so this can run inside the same transaction as
  # the write that made the cancellation necessary.
  @spec cancel_jobs(Ecto.Repo.t(), integer(), [String.t()]) :: {:ok, non_neg_integer()}
  defp cancel_jobs(repo, riddle_id, workers) do
    {count, _} =
      Oban.Job
      |> where([j], j.state in @cancellable_states)
      |> where([j], j.worker in ^workers)
      |> where([j], fragment("? @> ?", j.args, type(^%{"riddle_id" => riddle_id}, :map)))
      |> repo.update_all(set: [state: "cancelled", cancelled_at: Clock.utc_now()])

    {:ok, count}
  end

  @doc """
  Deletes a riddle, cancels its pending jobs and drops its unsent
  Notifications in one transaction, then clears its live state.
  """
  @spec delete(Riddle.t()) :: {:ok, Riddle.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Riddle{} = riddle) do
    Multi.new()
    |> Multi.run(:cancel_jobs, fn repo, _changes ->
      cancel_jobs(repo, riddle.id, drop_workers())
    end)
    |> Multi.delete(:riddle, riddle)
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: deleted}} ->
        Riddlr.Gameplay.cleanup_riddle(deleted.id)
        # Its solves went with it.
        Riddlr.Standings.invalidate()
        Games.refresh_home()

        Phoenix.PubSub.broadcast(
          Riddlr.PubSub,
          "games:riddle:changed",
          {:riddle_deleted, deleted}
        )

        if deleted.play_status in ["scheduled", "ready"] do
          broadcast_schedule_event(:riddle_unscheduled, deleted)
        end

        {:ok, deleted}

      {:error, _failed_operation, changeset, _changes} ->
        {:error, changeset}
    end
  end
end
