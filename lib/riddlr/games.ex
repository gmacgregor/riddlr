defmodule Riddlr.Games do
  @moduledoc """
  The Games context.

  The admin write functions (create, save, update and delete of riddles,
  categories and practice riddles) take a `Riddlr.Accounts.Scope` first. They
  return `{:error, :unauthorized}` unless the scope holds `:manage_riddles`.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Riddlr.Accounts.Scope
  alias Riddlr.Authorization
  alias Riddlr.Cache
  alias Riddlr.Clock
  alias Riddlr.Repo
  alias Riddlr.Games.Riddle
  alias Riddlr.Games.Category
  alias Riddlr.Games.Practice
  alias Riddlr.Games.PracticeRiddle
  alias Riddlr.Games.Transitions
  alias Riddlr.Games.RiddleName
  alias Riddlr.Notifications

  alias Riddlr.Workers.{
    ArchiveRiddleTransitionWorker,
    CompleteRiddleWorker,
    LiveRiddleTransitionWorker,
    NotificationFanOutWorker,
    ReadyRiddleTransitionWorker
  }

  # What every riddle read loads, and every broadcast riddle carries, so a
  # broadcast riddle equals a fetched one. Nothing reads first_solver.
  @riddle_preload [:category]

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
  Returns the newest riddles, newest first, at most `limit` (default 100).

  ## Examples

      iex> list_riddles()
      [%Riddle{}, ...]

  """
  @spec list_riddles(pos_integer()) :: [Riddle.t()]
  def list_riddles(limit \\ 100) do
    Riddle
    |> preload(^@riddle_preload)
    |> order_by([r], desc: r.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single riddle, with `:category` loaded. Pass `preload: [...]` to load
  other associations instead.

  Raises `Ecto.NoResultsError` if the Riddle does not exist.

  ## Examples

      iex> get_riddle!(123)
      %Riddle{}

      iex> get_riddle!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_riddle!(term(), keyword()) :: Riddle.t()
  def get_riddle!(id, opts \\ []) do
    Riddle
    |> preload(^Keyword.get(opts, :preload, @riddle_preload))
    |> Repo.get!(id)
  end

  @doc """
  Gets a single riddle, or `nil` if the Riddle does not exist.

  Takes the options `get_riddle!/2` takes.
  """
  @spec get_riddle(term(), keyword()) :: Riddle.t() | nil
  def get_riddle(id, opts \\ []) do
    Riddle
    |> preload(^Keyword.get(opts, :preload, @riddle_preload))
    |> Repo.get(id)
  end

  @doc """
  Fetches a riddle by ID, returning `{:ok, riddle}` or `{:error, :not_found}`. Rescues i.e Ecto.NoResultsError, Ecto.Query.CastError

  Takes the options `get_riddle!/2` takes.
  """
  @spec fetch_riddle(term(), keyword()) :: {:ok, Riddle.t()} | {:error, :not_found}
  def fetch_riddle(id, opts \\ []) do
    case get_riddle!(id, opts) do
      %Riddle{} = riddle -> {:ok, riddle}
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  @doc """
  Gets a riddle and takes a share lock on its row until the caller's
  transaction ends. Returns `nil` if the Riddle does not exist.

  The lock makes a save to the riddle wait for the caller's transaction, and
  makes the caller wait for a save already in flight. It must run inside a
  transaction. The riddle comes without preloads.
  """
  @spec lock_riddle_for_share(integer()) :: Riddle.t() | nil
  def lock_riddle_for_share(id) do
    Riddle
    |> where([r], r.id == ^id)
    |> lock("FOR SHARE")
    |> Repo.one()
  end

  @doc """
  Creates a riddle. A thin alias over `save_riddle/3` for seeds and fixtures —
  it schedules too, if the attrs say so.

  ## Examples

      iex> create_riddle(scope, %{field: value})
      {:ok, %Riddle{}}

      iex> create_riddle(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_riddle(Scope.t(), map()) ::
          {:ok, Riddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def create_riddle(%Scope{} = scope, attrs), do: save_riddle(scope, %Riddle{}, attrs)

  @doc """
  The one way to write a Riddle from the admin.

  Takes the row the admin edited (a bare `%Riddle{}` for a create) and the form
  attrs, and writes the row *and* its Oban jobs in a single transaction. The
  caller says nothing about scheduling: `save_riddle/3` reads the persisted
  state and the changeset and decides between four intents.

    * `:schedule` — a closed, published riddle with a future Live date
    * `:reschedule` — a scheduled/ready riddle whose Live date or lead time moved
    * `:unschedule` — a scheduled/ready riddle rolled back to draft
    * `:none` — a plain write

  A riddle that cannot be scheduled (draft, past Live date, already live) is not
  an error: it is simply not a schedule, and the row is written anyway.

  The scope must hold `:manage_riddles`.

  Returns `{:ok, riddle}`, `{:error, changeset}` or `{:error, :unauthorized}`.
  """
  @spec save_riddle(Scope.t(), Riddle.t(), map()) ::
          {:ok, Riddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def save_riddle(%Scope{} = scope, %Riddle{} = riddle, attrs) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      write_riddle(riddle, attrs)
    end
  end

  @spec write_riddle(Riddle.t(), map()) :: {:ok, Riddle.t()} | {:error, Ecto.Changeset.t()}
  defp write_riddle(riddle, attrs) do
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
  # That is what lets `save_riddle/3` return one error shape.
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
  defp announce(riddle, intent) do
    refresh_home()

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
      |> where([j], fragment("? @> ?", j.args, type(^%{"riddle_id" => riddle_id}, :map)))
      |> repo.update_all(set: [state: "cancelled", cancelled_at: Clock.utc_now()])

    {:ok, count}
  end

  @doc """
  Deletes a riddle.

  ## Examples

      iex> delete_riddle(scope, riddle)
      {:ok, %Riddle{}}

      iex> delete_riddle(scope, riddle)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_riddle(Scope.t(), Riddle.t()) ::
          {:ok, Riddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def delete_riddle(%Scope{} = scope, %Riddle{} = riddle) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      remove_riddle(riddle)
    end
  end

  @spec remove_riddle(Riddle.t()) :: {:ok, Riddle.t()} | {:error, Ecto.Changeset.t()}
  defp remove_riddle(riddle) do
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
        refresh_home()

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

  @doc "Returns a blank riddle for a new-riddle form."
  @spec new_riddle() :: Riddle.t()
  def new_riddle, do: %Riddle{}

  @doc "Returns a random riddle name, such as a new riddle gets."
  @spec generate_riddle_name() :: String.t()
  defdelegate generate_riddle_name, to: RiddleName, as: :generate

  @doc "The difficulty values a riddle may take."
  @spec riddle_difficulties() :: [String.t()]
  defdelegate riddle_difficulties, to: Riddle, as: :difficulties

  @doc "The publish status values a riddle may take."
  @spec riddle_publish_statuses() :: [String.t()]
  defdelegate riddle_publish_statuses, to: Riddle, as: :publish_statuses

  @doc "The hint delay a new riddle starts with."
  @spec default_hint_delay() :: non_neg_integer()
  defdelegate default_hint_delay, to: Riddle

  @doc "The solve time a new riddle starts with."
  @spec default_solve_time() :: pos_integer()
  defdelegate default_solve_time, to: Riddle

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
  The riddle players can join next: the published riddle that is `scheduled`,
  `ready` or `live` with the soonest Live date, category preloaded. A live
  riddle's Live date has passed, so it comes before any upcoming one. Returns
  nil when there is none.
  """
  @spec next_riddle() :: Riddle.t() | nil
  def next_riddle do
    next_query()
    |> preload(:category)
    |> Repo.one()
  end

  @doc """
  Up to `limit` riddles not yet live: published, `scheduled` or `ready`,
  soonest Live date first, category preloaded. The next riddle
  (`next_riddle/0`) is among them unless it is live.
  """
  @spec list_upcoming_riddles(pos_integer()) :: [Riddle.t()]
  def list_upcoming_riddles(limit) when is_integer(limit) and limit > 0 do
    Riddle
    |> where([r], r.publish_status == "published")
    |> where([r], r.play_status in ["scheduled", "ready"])
    |> order_by([r], asc: r.live_date, asc: r.id)
    |> limit(^limit)
    |> preload(:category)
    |> Repo.all()
  end

  @doc """
  The most recent finished riddle: the `completed` or `archived` one with the
  latest Live date, category preloaded. Returns nil when no riddle has
  finished. Its first solver and time come from `Gameplay.first_solve/1`.
  """
  @spec last_finished_riddle() :: Riddle.t() | nil
  def last_finished_riddle do
    Riddle
    |> where([r], r.play_status in ["completed", "archived"])
    |> order_by([r], desc_nulls_last: r.live_date, desc: r.id)
    |> limit(1)
    |> preload(:category)
    |> Repo.one()
  end

  @typedoc """
  Everything Home shows that comes from the database: the next riddle, the
  riddles coming up, the last finished riddle and its first solve (`:user`
  loaded), and every practice riddle, oldest first.
  """
  @type home_snapshot :: %{
          next: Riddle.t() | nil,
          upcoming: [Riddle.t()],
          last: Riddle.t() | nil,
          last_solve: Riddlr.Gameplay.Solve.t() | nil,
          practice: [PracticeRiddle.t()]
        }

  # How many riddles Home lists after the next one.
  @home_upcoming 3

  @doc """
  What Home shows, from `Riddlr.Cache`.

  Every write here that Home could show (a save, a schedule change, a
  transition, a delete, a practice riddle change) rebuilds it before it
  broadcasts, so every Home view that reloads on the broadcast reads it
  warm. A miss reads the database and fills the cache.
  """
  @spec home_snapshot() :: home_snapshot()
  def home_snapshot, do: Cache.fetch(:home, &build_home_snapshot/0)

  @doc """
  Rebuilds the Home snapshot in `Riddlr.Cache`. Every write Home could show
  calls this before it broadcasts.
  """
  @spec refresh_home() :: :ok
  def refresh_home, do: Cache.put(:home, build_home_snapshot())

  @spec build_home_snapshot() :: home_snapshot()
  defp build_home_snapshot do
    last = last_finished_riddle()

    %{
      next: next_riddle(),
      upcoming: list_upcoming_riddles(@home_upcoming),
      last: last,
      last_solve: last && Riddlr.Gameplay.first_solve(last.id),
      practice: Practice.list()
    }
  end

  # The query behind `next_riddle/0`: at most one row.
  @spec next_query() :: Ecto.Query.t()
  defp next_query do
    Riddle
    |> where([r], r.publish_status == "published")
    |> where([r], r.play_status in ["scheduled", "ready", "live"])
    |> order_by([r], asc: r.live_date, asc: r.id)
    |> limit(1)
  end

  @doc """
  Records the first solver of a riddle (no-op if already set).
  Uses atomic update to avoid race conditions.
  Optionally stores `first_solve_time` (milliseconds from live_date) in the same operation.
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
  Loads what every riddle read loads, so a broadcast riddle equals a fetched
  one.
  """
  @spec preload_riddle(Riddle.t()) :: Riddle.t()
  def preload_riddle(%Riddle{} = riddle), do: Repo.preload(riddle, @riddle_preload)

  defp preload_assoc_force(%Riddle{} = riddle) do
    Repo.preload(riddle, @riddle_preload, force: true)
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

      iex> create_category(scope, %{field: value})
      {:ok, %Category{}}

      iex> create_category(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_category(Scope.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def create_category(%Scope{} = scope, attrs) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      %Category{}
      |> Category.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(scope, category, %{field: new_value})
      {:ok, %Category{}}

      iex> update_category(scope, category, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_category(Scope.t(), Category.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def update_category(%Scope{} = scope, %Category{} = category, attrs) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      category
      |> Category.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a category.

  ## Examples

      iex> delete_category(scope, category)
      {:ok, %Category{}}

      iex> delete_category(scope, category)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_category(Scope.t(), Category.t()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def delete_category(%Scope{} = scope, %Category{} = category) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      Repo.delete(category)
    end
  end

  @doc "Returns a blank category for a new-category form."
  @spec new_category() :: Category.t()
  def new_category, do: %Category{}

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.

  ## Examples

      iex> change_category(category)
      %Ecto.Changeset{data: %Category{}}

  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  @doc """
  Transitions a riddle's play status. See `Riddlr.Games.Transitions.transition/3`.
  """
  @spec transition(integer(), Transitions.status(), map()) :: Transitions.result()
  defdelegate transition(riddle_id, to, stats \\ %{}), to: Transitions

  # Practice riddles live in Riddlr.Games.Practice.

  @spec list_practice_riddles() :: [PracticeRiddle.t()]
  defdelegate list_practice_riddles, to: Practice, as: :list

  @spec create_practice_riddle(Scope.t(), map()) ::
          {:ok, PracticeRiddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  defdelegate create_practice_riddle(scope, attrs), to: Practice, as: :create

  @spec get_practice_riddle!(integer() | String.t()) :: PracticeRiddle.t()
  defdelegate get_practice_riddle!(id), to: Practice, as: :get!

  @spec get_practice_riddle(integer()) :: PracticeRiddle.t() | nil
  defdelegate get_practice_riddle(id), to: Practice, as: :get

  @spec update_practice_riddle(Scope.t(), PracticeRiddle.t(), map()) ::
          {:ok, PracticeRiddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  defdelegate update_practice_riddle(scope, practice_riddle, attrs), to: Practice, as: :update

  @spec delete_practice_riddle(Scope.t(), PracticeRiddle.t()) ::
          {:ok, PracticeRiddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  defdelegate delete_practice_riddle(scope, practice_riddle), to: Practice, as: :delete

  @spec new_practice_riddle() :: PracticeRiddle.t()
  defdelegate new_practice_riddle, to: Practice, as: :new

  @spec change_practice_riddle(PracticeRiddle.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_practice_riddle(practice_riddle, attrs \\ %{}), to: Practice, as: :change

  @spec random_practice_riddle(integer() | nil) :: PracticeRiddle.t() | nil
  defdelegate random_practice_riddle(exclude_id \\ nil), to: Practice, as: :random

  @spec count_practice_riddles() :: non_neg_integer()
  defdelegate count_practice_riddles, to: Practice, as: :count

  @spec practice_riddle_number(PracticeRiddle.t()) :: non_neg_integer()
  defdelegate practice_riddle_number(practice_riddle), to: Practice, as: :number
end
