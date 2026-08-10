defmodule Riddlr.Games do
  @moduledoc """
  The Games context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Riddlr.Repo
  alias Riddlr.Games.Riddle
  alias Riddlr.Games.Category

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
  Creates a riddle.

  ## Examples

      iex> create_riddle(%{field: value})
      {:ok, %Riddle{}}

      iex> create_riddle(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_riddle(attrs \\ %{}) do
    %Riddle{}
    |> Riddle.changeset(attrs)
    |> Repo.insert()
    |> case do
      # preload category so that it's name can be referenced in display
      {:ok, riddle} -> {:ok, preload_assoc(riddle)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Updates a riddle.
  If publish_status changes from "published" to "draft", cancels all pending jobs.

  ## Examples

      iex> update_riddle(riddle, %{field: new_value})
      {:ok, %Riddle{}}

      iex> update_riddle(riddle, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_riddle(%Riddle{} = riddle, attrs) do
    changeset = Riddle.changeset(riddle, attrs)

    publish_status_changing_to_draft? =
      riddle.publish_status == "published" &&
        Ecto.Changeset.get_change(changeset, :publish_status) == "draft"

    # If rolling back to draft from a scheduled/ready state, also reset play_status to closed
    changeset =
      if publish_status_changing_to_draft? && riddle.play_status in ["scheduled", "ready"] do
        Ecto.Changeset.put_change(changeset, :play_status, "closed")
      else
        changeset
      end

    Multi.new()
    |> Multi.update(:riddle, changeset)
    |> Multi.run(:cancel_jobs, fn _repo, %{riddle: updated_riddle} ->
      if publish_status_changing_to_draft? do
        cancel_riddle_jobs(updated_riddle.id)
      else
        {:ok, :skipped}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: riddle}} -> {:ok, preload_assoc_force(riddle)}
      {:error, :riddle, changeset, _} -> {:error, changeset}
      {:error, _failed_operation, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Cancels all pending Oban jobs for a riddle.
  Returns {:ok, count} where count is the number of cancelled jobs.
  """
  def cancel_riddle_jobs(riddle_id) do
    {count, _} =
      Oban.Job
      |> where([j], j.state in ["available", "scheduled", "retryable"])
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
      |> Repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])

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
    case Repo.delete(riddle) do
      {:ok, deleted} ->
        Riddlr.Gameplay.cleanup_riddle(deleted.id)
        {:ok, deleted}

      {:error, changeset} ->
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
  Schedules a riddle to go live at the specified date.
  Transitions: closed → scheduled
  Enqueues ReadyRiddleTransitionWorker (ready_before_seconds before live) and LiveRiddleTransitionWorker (at live_date).
  """
  def schedule_riddle(%Riddle{} = riddle, live_date, attrs \\ %{}) do
    effective_publish_status =
      Map.get(attrs, :publish_status) || Map.get(attrs, "publish_status", riddle.publish_status)

    cond do
      effective_publish_status != "published" ->
        {:error, :riddle_not_published}

      DateTime.compare(live_date, DateTime.utc_now()) == :lt ->
        {:error, :live_date_in_past}

      riddle.play_status != "closed" ->
        {:error, "cannot schedule riddle in #{riddle.play_status} state"}

      true ->
        schedule_attrs =
          Map.merge(attrs, %{"play_status" => "scheduled", "live_date" => live_date})

        multi =
          Multi.new()
          |> Multi.update(
            :riddle,
            Riddle.changeset(riddle, schedule_attrs)
          )
          |> Multi.insert(:ready_job, fn %{riddle: updated_riddle} ->
            %{"riddle_id" => updated_riddle.id}
            |> Riddlr.Workers.ReadyRiddleTransitionWorker.new(
              scheduled_at: DateTime.add(live_date, -updated_riddle.ready_before_seconds, :second)
            )
          end)
          |> Multi.insert(:live_job, fn %{riddle: updated_riddle} ->
            %{"riddle_id" => updated_riddle.id}
            |> Riddlr.Workers.LiveRiddleTransitionWorker.new(scheduled_at: live_date)
          end)

        case Repo.transaction(multi) do
          {:ok, %{riddle: updated_riddle} = result} ->
            broadcast_riddle = preload_assoc(updated_riddle)

            Phoenix.PubSub.broadcast(
              Riddlr.PubSub,
              "games:riddle:scheduled",
              {:riddle_scheduled, broadcast_riddle}
            )

            {:ok, Map.put(result, :broadcast, :broadcasted)}

          {:error, _failed_operation, _failed_value, _changes} = error ->
            error
        end
    end
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
    * `{:invalid, from, to}` — forbidden by `Riddle.valid_transitions/0`, or a
      `live_until_solved` riddle asked to complete without a solver
    * `{:error, changeset}` — the write failed

  The three non-changeset failures are permanent: callers should not retry.
  """
  def transition(riddle_id, to, stats \\ %{}) do
    with {:ok, riddle} <- fetch_transitionable(riddle_id, to, stats) do
      riddle
      |> run_transition(to, stats)
      |> after_commit(to)
    end
  end

  defp fetch_transitionable(riddle_id, to, stats) do
    case Repo.get(Riddle, riddle_id) do
      nil ->
        {:error, :not_found}

      %Riddle{publish_status: publish_status} when publish_status != "published" ->
        {:unpublished, publish_status}

      riddle ->
        if allowed?(riddle, to, stats) do
          {:ok, riddle}
        else
          {:invalid, riddle.play_status, to}
        end
    end
  end

  defp allowed?(riddle, to, stats) do
    Riddle.can_transition?(riddle.play_status, to) and solve_satisfied?(riddle, to, stats)
  end

  # A live_until_solved riddle has no timer: it completes only on a solve, and a
  # solve is what puts :first_solver_id in the stats.
  defp solve_satisfied?(%Riddle{live_until_solved: true}, :completed, stats),
    do: Map.has_key?(stats, :first_solver_id)

  defp solve_satisfied?(_riddle, _to, _stats), do: true

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
    Multi.run(multi, :complete_job, fn _repo, %{riddle: riddle} ->
      if riddle.live_until_solved do
        {:ok, :skipped}
      else
        %{"riddle_id" => riddle.id}
        |> Riddlr.Workers.CompleteRiddleWorker.new(schedule_in: riddle.solve_time)
        |> Oban.insert()
      end
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

  @doc """
  Atomically claims first-solver status and immediately completes the riddle.
  Uses `record_first_solver/2`'s conditional DB write as the concurrency gate —
  only the caller that successfully sets first_solver_id proceeds with completion.

  Stats map may include: first_solve_time, completion_rate.
  first_solver_id is set internally from user_id.

  Returns {:ok, riddle} on success, {:ok, :skipped} if another caller won the race,
  or {:error, reason} on failure.
  """
  def complete_riddle_on_first_solve(riddle_id, user_id, stats \\ %{}) do
    case record_first_solver(riddle_id, user_id) do
      {:ok, :recorded} ->
        cancel_complete_worker(riddle_id)
        transition(riddle_id, :completed, Map.put(stats, :first_solver_id, user_id))

      {:ok, :already_set} ->
        {:ok, :skipped}
    end
  end

  @doc """
  Cancels any pending CompleteRiddleWorker jobs for a riddle.
  Called when the first correct answer triggers immediate completion.
  Returns {:ok, count} where count is the number of cancelled jobs.
  """
  def cancel_complete_worker(riddle_id) do
    {count, _} =
      Oban.Job
      |> where([j], j.state in ["available", "scheduled", "retryable"])
      |> where([j], j.worker == ^"Riddlr.Workers.CompleteRiddleWorker")
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
      |> Repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])

    {:ok, count}
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
