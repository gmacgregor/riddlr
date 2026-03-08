defmodule Riddlr.Games do
  @moduledoc """
  The Games context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Riddlr.Repo

  alias Riddlr.Games.Riddle

  @minutes_before_live 5
  @seconds_before_live @minutes_before_live * 60

  @doc """
  Returns the list of riddles.

  ## Examples

      iex> list_riddles()
      [%Riddle{}, ...]

  """
  def list_riddles do
    Riddle
    |> preload(:category)
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
    |> preload(:category)
    |> Repo.get!(id)
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
    Repo.delete(riddle)
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
  Enqueues ReadyRiddleTransitionWorker (5 min before live) and LiveRiddleTransitionWorker (at live_date).
  """
  def schedule_riddle(%Riddle{} = riddle, live_date) do
    cond do
      DateTime.compare(live_date, DateTime.utc_now()) == :lt ->
        {:error, :live_date_in_past}

      riddle.play_status != "closed" ->
        {:error, "cannot schedule riddle in #{riddle.play_status} state"}

      true ->
        Multi.new()
        |> Multi.update(
          :riddle,
          Riddle.changeset(riddle, %{
            play_status: "scheduled",
            live_date: live_date
          })
        )
        |> Multi.insert(:ready_job, fn %{riddle: updated_riddle} ->
          %{"riddle_id" => updated_riddle.id}
          |> Riddlr.Workers.ReadyRiddleTransitionWorker.new(
            scheduled_at: DateTime.add(live_date, -@seconds_before_live, :second)
          )
        end)
        |> Multi.insert(:live_job, fn %{riddle: updated_riddle} ->
          %{"riddle_id" => updated_riddle.id}
          |> Riddlr.Workers.LiveRiddleTransitionWorker.new(scheduled_at: live_date)
        end)
        |> Multi.run(:broadcast, fn _, %{riddle: updated_riddle} ->
          Phoenix.PubSub.broadcast(
            Riddlr.PubSub,
            "games:riddle:scheduled",
            {:riddle_scheduled, updated_riddle}
          )

          {:ok, :broadcasted}
        end)
        |> Repo.transaction()
    end
  end

  @doc """
  Transitions a riddle to ready state (@minutes_before_live minutes before live).
  Transitions: scheduled → ready
  """
  def ready_riddle(riddle_id) do
    case Repo.get(Riddle, riddle_id) do
      nil ->
        {:error, :not_found}

      riddle ->
        if riddle.play_status != "scheduled" do
          {:error, "cannot transition from #{riddle.play_status} to ready"}
        else
          Multi.new()
          |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: "ready"}))
          |> Multi.run(:broadcast, fn _, %{riddle: updated_riddle} ->
            # Preload category for LiveView rendering
            updated_riddle = preload_assoc(updated_riddle)

            Phoenix.PubSub.broadcast(
              Riddlr.PubSub,
              "games:riddle:ready",
              {:riddle_ready, updated_riddle}
            )

            {:ok, :broadcasted}
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{riddle: riddle}} -> {:ok, riddle}
            {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
          end
        end
    end
  end

  @doc """
  Starts a riddle (transitions to live state).
  Transitions: ready → live
  Enqueues CompleteRiddleWorker after solve_time seconds unless live_until_solved is true.
  """
  def start_riddle(riddle_id) do
    case Repo.get(Riddle, riddle_id) do
      nil ->
        {:error, :not_found}

      riddle ->
        if riddle.play_status != "ready" do
          {:error, "cannot transition from #{riddle.play_status} to live"}
        else
          multi =
            Multi.new()
            |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: "live"}))
            |> Multi.run(:broadcast, fn _, %{riddle: updated_riddle} ->
              # Preload category for LiveView rendering
              updated_riddle = preload_assoc(updated_riddle)

              Phoenix.PubSub.broadcast(
                Riddlr.PubSub,
                "games:riddle:live",
                {:riddle_live, updated_riddle}
              )

              {:ok, :broadcasted}
            end)

          multi =
            if riddle.live_until_solved do
              multi
            else
              Multi.insert(multi, :complete_job, fn %{riddle: updated_riddle} ->
                %{"riddle_id" => updated_riddle.id}
                |> Riddlr.Workers.CompleteRiddleWorker.new(schedule_in: updated_riddle.solve_time)
              end)
            end

          multi
          |> Repo.transaction()
          |> case do
            {:ok, %{riddle: riddle}} -> {:ok, riddle}
            {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
          end
        end
    end
  end

  @doc """
  Completes a riddle (marks as completed after solve_time expires).
  Transitions: live → completed
  Enqueues ArchiveRiddleTransitionWorker (3 min delay).
  """
  def complete_riddle(riddle_id) do
    case Repo.get(Riddle, riddle_id) do
      nil ->
        {:error, :not_found}

      riddle ->
        cond do
          riddle.play_status != "live" ->
            {:error, "cannot transition from #{riddle.play_status} to completed"}

          true ->
            Multi.new()
            |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: "completed"}))
            |> Multi.insert(:archive_job, fn %{riddle: updated_riddle} ->
              # Use the riddle's configured cooldown (in seconds)
              cooldown_seconds = updated_riddle.archive_cooldown_minutes * 60

              %{"riddle_id" => updated_riddle.id}
              |> Riddlr.Workers.ArchiveRiddleTransitionWorker.new(schedule_in: cooldown_seconds)
            end)
            |> Multi.run(:broadcast, fn _, %{riddle: updated_riddle} ->
              # Preload category for LiveView rendering
              updated_riddle = preload_assoc(updated_riddle)

              Phoenix.PubSub.broadcast(
                Riddlr.PubSub,
                "games:riddle:completed",
                {:riddle_completed, updated_riddle}
              )

              {:ok, :broadcasted}
            end)
            |> Repo.transaction()
            |> case do
              {:ok, %{riddle: riddle}} -> {:ok, riddle}
              {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
            end
        end
    end
  end

  @doc """
  Archives a riddle (final state after 3 min cooling period).
  Transitions: completed → archived
  """
  def archive_riddle(riddle_id) do
    case Repo.get(Riddle, riddle_id) do
      nil ->
        {:error, :not_found}

      riddle ->
        if riddle.play_status != "completed" do
          {:error, "cannot transition from #{riddle.play_status} to archived"}
        else
          Multi.new()
          |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: "archived"}))
          |> Multi.run(:broadcast, fn _, %{riddle: updated_riddle} ->
            # Preload category for LiveView rendering
            updated_riddle = preload_assoc(updated_riddle)

            Phoenix.PubSub.broadcast(
              Riddlr.PubSub,
              "games:riddle:archived",
              {:riddle_archived, updated_riddle}
            )

            {:ok, :broadcasted}
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{riddle: riddle}} -> {:ok, riddle}
            {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
          end
        end
    end
  end

  @doc """
  Records the first solver of a riddle (no-op if already set).
  Uses atomic update to avoid race conditions.
  """
  def record_first_solver(riddle_id, user_id) do
    {count, _} =
      from(r in Riddle,
        where: r.id == ^riddle_id and is_nil(r.first_solver_id)
      )
      |> Repo.update_all(set: [first_solver_id: user_id])

    if count > 0, do: {:ok, :recorded}, else: {:ok, :already_set}
  end

  defp preload_assoc(%Riddle{} = riddle) do
    Repo.preload(riddle, :category)
  end

  defp preload_assoc_force(%Riddle{} = riddle) do
    Repo.preload(riddle, :category, force: true)
  end

  alias Riddlr.Games.Category

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
