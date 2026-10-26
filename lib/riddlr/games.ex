defmodule Riddlr.Games do
  @moduledoc """
  The Games context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Riddlr.Clock
  alias Riddlr.Repo
  alias Riddlr.Games.Riddle
  alias Riddlr.Games.Category

  alias Riddlr.Workers.{
    ArchiveRiddleTransitionWorker,
    CompleteRiddleWorker,
    LiveRiddleTransitionWorker,
    ReadyRiddleTransitionWorker
  }

  # The four workers that take a riddle_id argument. Cancelling a riddle's
  # pending work means cancelling jobs from this list, which is why it exists as
  # one list rather than a filter written out at each call site.
  #
  # Stored as strings because Oban's `worker` column holds the module name
  # without the `Elixir.` prefix — which is what `inspect/1` produces and
  # `to_string/1` does not.
  @riddle_workers Enum.map(
                    [
                      ReadyRiddleTransitionWorker,
                      LiveRiddleTransitionWorker,
                      ArchiveRiddleTransitionWorker,
                      CompleteRiddleWorker
                    ],
                    &inspect/1
                  )

  # A job in any other state has already run, been cancelled or been discarded,
  # so there is nothing left to cancel.
  @cancellable_states ["available", "scheduled", "retryable"]

  @doc """
  Returns the list of riddles.

  ## Examples

      iex> list_riddles()
      [%Riddle{}, ...]

  """
  def list_riddles do
    Riddle
    |> preload([:category, :first_solver])
    |> order_by([c], desc: c.inserted_at, desc: c.play_status)
    |> Repo.all()
  end

  @doc """
  Gets a single riddle.

  Raises `Ecto.NoResultsError` if the Riddle does not exist.

  ## Examples

      iex> get_riddle!(123)
      %Riddle{}

      iex> get_riddle!(456)
      ** (Ecto.NoResultsError)

  """
  def get_riddle!(id) do
    Riddle
    |> preload([:category, :first_solver])
    |> Repo.get!(id)
  end

  @doc """
  Fetches a riddle by ID, returning `{:ok, riddle}` or `{:error, :not_found}`. Rescues i.e Ecto.NoResultsError, Ecto.Query.CastError
  """
  @spec fetch_riddle(term()) :: {:ok, Riddle.t()} | {:error, :not_found}
  def fetch_riddle(id) do
    case get_riddle!(id) do
      %Riddle{} = riddle -> {:ok, riddle}
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  @doc """
  Creates a riddle. A thin alias over `save_riddle/2` for seeds and fixtures —
  it schedules too, if the attrs say so.

  ## Examples

      iex> create_riddle(%{field: value})
      {:ok, %Riddle{}}

      iex> create_riddle(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_riddle(attrs \\ %{}), do: save_riddle(%Riddle{}, attrs)

  @doc """
  The one way to write a Riddle from the admin.

  Takes the row the admin edited (a bare `%Riddle{}` for a create) and the form
  attrs, and writes the row *and* its Oban jobs in a single transaction. The
  caller says nothing about scheduling: `save_riddle/2` reads the persisted
  state and the changeset and decides between four intents.

    * `:schedule` — a closed, published riddle with a future Live date
    * `:reschedule` — a scheduled/ready riddle whose Live date or lead time moved
    * `:unschedule` — a scheduled/ready riddle rolled back to draft
    * `:none` — a plain write

  A riddle that cannot be scheduled (draft, past Live date, already live) is not
  an error: it is simply not a schedule, and the row is written anyway.

  Returns `{:ok, riddle}` or `{:error, changeset}` — no other shape.
  """
  def save_riddle(%Riddle{} = riddle, attrs) do
    changeset = Riddle.changeset(riddle, attrs)

    # An invalid changeset gets `:none`: the transaction will roll back anyway,
    # and skipping the intent avoids running the validations twice and doubling
    # every error message in the form.
    intent = if changeset.valid?, do: intent(riddle, changeset), else: :none

    Multi.new()
    |> Multi.insert_or_update(:riddle, apply_intent(changeset, intent))
    |> write_jobs(intent)
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: saved}} -> {:ok, saved |> preload_assoc_force() |> announce(intent)}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
  end

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
  # That is what lets `save_riddle/2` return one error shape.
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
  defp unscheduling?(%Riddle{play_status: play_status}, changeset)
       when play_status in ["scheduled", "ready"],
       do: Ecto.Changeset.get_field(changeset, :publish_status) != "published"

  defp unscheduling?(_riddle, _changeset), do: false

  # The two fields the pending jobs are derived from — `live_date` sets the live
  # job and, minus the lead time, the ready job. Either one moving means the jobs
  # on disk no longer match the row, so both are rewritten.
  defp schedule_moved?(changeset) do
    Enum.any?([:live_date, :ready_before_seconds], fn field ->
      not is_nil(Ecto.Changeset.get_change(changeset, field))
    end)
  end

  # The intent is also a Play status change. Re-running `Riddle.changeset/2` over
  # the changeset (rather than `put_change/3`) keeps the transition table in
  # `Riddle` the only judge of whether the move is legal.
  defp apply_intent(changeset, :schedule),
    do: Riddle.changeset(changeset, %{play_status: "scheduled"})

  defp apply_intent(changeset, :unschedule),
    do: Riddle.changeset(changeset, %{play_status: "closed"})

  defp apply_intent(changeset, _intent), do: changeset

  defp write_jobs(multi, intent) when intent in [:schedule, :reschedule] do
    multi
    |> Multi.run(:cancel_jobs, fn repo, %{riddle: riddle} ->
      cancel_jobs(repo, riddle.id, @riddle_workers)
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
  end

  defp write_jobs(multi, :unschedule) do
    Multi.run(multi, :cancel_jobs, fn repo, %{riddle: riddle} ->
      cancel_jobs(repo, riddle.id, @riddle_workers)
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
  defp announce(riddle, intent) do
    Phoenix.PubSub.broadcast(Riddlr.PubSub, "games:riddle:changed", {:riddle_saved, riddle})

    case schedule_event(intent) do
      nil -> :ok
      message -> broadcast_schedule_event(message, riddle)
    end

    riddle
  end

  defp broadcast_schedule_event(message, riddle) do
    Phoenix.PubSub.broadcast(Riddlr.PubSub, "games:riddle:scheduled", {message, riddle})
  end

  defp schedule_event(:schedule), do: :riddle_scheduled
  defp schedule_event(:reschedule), do: :riddle_rescheduled
  defp schedule_event(:unschedule), do: :riddle_unscheduled
  defp schedule_event(_intent), do: nil

  # The one place that cancels a riddle's jobs. Callers pass the worker list they
  # want cancelled, and the repo, so this can run inside the same transaction as
  # the write that made the cancellation necessary.
  defp cancel_jobs(repo, riddle_id, workers) do
    {count, _} =
      Oban.Job
      |> where([j], j.state in @cancellable_states)
      |> where([j], j.worker in ^workers)
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
      |> repo.update_all(set: [state: "cancelled", cancelled_at: Clock.utc_now()])

    {:ok, count}
  end

  @doc """
  Deletes a riddle.

  ## Examples

      iex> delete_riddle(riddle)
      {:ok, %Riddle{}}

      iex> delete_riddle(riddle)
      {:error, %Ecto.Changeset{}}

  """
  def delete_riddle(%Riddle{} = riddle) do
    Multi.new()
    |> Multi.run(:cancel_jobs, fn repo, _changes ->
      cancel_jobs(repo, riddle.id, @riddle_workers)
    end)
    |> Multi.delete(:riddle, riddle)
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: deleted}} ->
        Riddlr.Gameplay.cleanup_riddle(deleted.id)

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

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking riddle changes.

  ## Examples

      iex> change_riddle(riddle)
      %Ecto.Changeset{data: %Riddle{}}

  """
  def change_riddle(%Riddle{} = riddle, attrs \\ %{}) do
    Riddle.changeset(riddle, attrs)
  end

  @doc """
  Transitions a riddle's play status.

  One interface for every Play status transition: it owns the guards, the write,
  the follow-on job, the broadcast and any cleanup. Callers (Oban workers,
  Gameplay) supply only the target status and, for `:completed`, stats.

  Returns:

    * `{:ok, riddle}` — transitioned and committed
    * `{:error, :not_found}` — no such riddle
    * `{:unpublished, publish_status}` — riddle is not published
    * `{:invalid, from, to}` — forbidden by `Riddle.valid_transitions/0`
    * `{:error, changeset}` — the write failed

  The three non-changeset failures are permanent: callers should not retry.
  """
  def transition(riddle_id, to, stats \\ %{}) do
    with {:ok, riddle} <- fetch_transitionable(riddle_id, to) do
      riddle
      |> run_transition(to, stats)
      |> after_commit(to)
    end
  end

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

  defp run_transition(riddle, to, stats) do
    Multi.new()
    |> Multi.update(:riddle, Riddle.changeset(riddle, transition_attrs(to, stats)))
    |> enqueue_next_job(to)
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: riddle}} -> {:ok, riddle}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
  end

  defp enqueue_next_job(multi, :live) do
    Multi.insert(multi, :complete_job, fn %{riddle: riddle} ->
      %{"riddle_id" => riddle.id}
      |> Riddlr.Workers.CompleteRiddleWorker.new(schedule_in: riddle.solve_time)
    end)
  end

  defp enqueue_next_job(multi, :completed) do
    Multi.insert(multi, :archive_job, fn %{riddle: riddle} ->
      %{"riddle_id" => riddle.id}
      |> Riddlr.Workers.ArchiveRiddleTransitionWorker.new(
        schedule_in: riddle.archive_after_seconds
      )
    end)
  end

  defp enqueue_next_job(multi, _to), do: multi

  defp transition_attrs(:completed, stats) do
    stats
    |> Map.take([:first_solver_id, :first_solve_time, :completion_rate])
    |> Map.put(:play_status, "completed")
  end

  defp transition_attrs(to, _stats), do: %{play_status: to_string(to)}

  # Everything that must not happen until the transaction has committed:
  # broadcasting a rolled-back transition would move every Lobby to a riddle
  # that never went live.
  defp after_commit({:ok, riddle}, to) do
    cleanup(to, riddle)

    broadcast_riddle = preload_assoc(riddle)
    {topic, message} = broadcast_for(to)

    Phoenix.PubSub.broadcast(Riddlr.PubSub, topic, {message, broadcast_riddle})

    {:ok, riddle}
  end

  defp after_commit(other, _to), do: other

  # An archived riddle takes no more answers, so its ETS rows are dead weight.
  defp cleanup(:archived, riddle), do: Riddlr.Gameplay.cleanup_riddle(riddle.id)
  defp cleanup(_to, _riddle), do: :ok

  defp broadcast_for(:ready), do: {"games:riddle:ready", :riddle_ready}
  defp broadcast_for(:live), do: {"games:riddle:live", :riddle_live}
  defp broadcast_for(:completed), do: {"games:riddle:completed", :riddle_completed}
  defp broadcast_for(:archived), do: {"games:riddle:archived", :riddle_archived}

  @doc """
  Records the first solver of a riddle (no-op if already set).
  Uses atomic update to avoid race conditions.
  Optionally stores `first_solve_time` (seconds from live_date) in the same operation.
  """
  def record_first_solver(riddle_id, user_id, first_solve_time \\ nil) do
    updates =
      if first_solve_time,
        do: [first_solver_id: user_id, first_solve_time: first_solve_time],
        else: [first_solver_id: user_id]

    {count, _} =
      from(r in Riddle,
        where: r.id == ^riddle_id and is_nil(r.first_solver_id)
      )
      |> Repo.update_all(set: updates)

    if count > 0, do: {:ok, :recorded}, else: {:ok, :already_set}
  end

  defp preload_assoc(%Riddle{} = riddle) do
    Repo.preload(riddle, [:category, :first_solver])
  end

  defp preload_assoc_force(%Riddle{} = riddle) do
    Repo.preload(riddle, [:category, :first_solver], force: true)
  end

  @doc """
  Returns the list of categories.

  ## Examples

      iex> list_categories()
      [%Category{}, ...]

  """
  def list_categories do
    Repo.all(from c in Category, order_by: c.name)
  end

  @doc """
  Gets a single category.

  Raises `Ecto.NoResultsError` if the Category does not exist.

  ## Examples

      iex> get_category!(123)
      %Category{}

      iex> get_category!(456)
      ** (Ecto.NoResultsError)

  """
  def get_category!(id), do: Repo.get!(Category, id)

  @doc """
  Creates a category.

  ## Examples

      iex> create_category(%{field: value})
      {:ok, %Category{}}

      iex> create_category(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(category, %{field: new_value})
      {:ok, %Category{}}

      iex> update_category(category, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.

  ## Examples

      iex> delete_category(category)
      {:ok, %Category{}}

      iex> delete_category(category)
      {:error, %Ecto.Changeset{}}

  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.

  ## Examples

      iex> change_category(category)
      %Ecto.Changeset{data: %Category{}}

  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end
end
