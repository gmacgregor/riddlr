defmodule Riddlr.Games do
  @moduledoc """
  The Games context.

  The admin write functions (create, save, update and delete of riddles,
  categories, seasons and practice riddles) take a `Riddlr.Accounts.Scope` first. They
  return `{:error, :unauthorized}` unless the scope holds `:manage_riddles`.
  """

  import Ecto.Query, warn: false

  alias Riddlr.Accounts.Scope
  alias Riddlr.Authorization
  alias Riddlr.Cache
  alias Riddlr.Repo
  alias Riddlr.Games.Riddle
  alias Riddlr.Games.Category
  alias Riddlr.Games.Season
  alias Riddlr.Games.Practice
  alias Riddlr.Games.PracticeRiddle
  alias Riddlr.Games.Transitions
  alias Riddlr.Games.RiddleName
  alias Riddlr.Games.Schedule

  # What every riddle read loads, and every broadcast riddle carries, so a
  # broadcast riddle equals a fetched one. Nothing reads first_solver.
  @riddle_preload [:category, :season]

  @doc """
  Returns riddles with the given publish status, at most `limit` (default 100).

  The latest live date comes first and riddles with no live date come last.
  Riddles with the same live date come newest first.

  ## Examples

      iex> list_riddles("published")
      [%Riddle{}, ...]

  """
  @spec list_riddles(String.t(), pos_integer()) :: [Riddle.t()]
  def list_riddles(publish_status, limit \\ 100) do
    Riddle
    |> where([r], r.publish_status == ^publish_status)
    |> preload(^@riddle_preload)
    |> order_by([r], desc_nulls_last: r.live_date, desc: r.inserted_at, desc: r.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Counts riddles per publish status, with no limit. A status with no riddles
  is absent from the map.

  ## Examples

      iex> count_riddles_by_status()
      %{"draft" => 3, "published" => 12}

  """
  @spec count_riddles_by_status() :: %{String.t() => non_neg_integer()}
  def count_riddles_by_status do
    Riddle
    |> group_by([r], r.publish_status)
    |> select([r], {r.publish_status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets a single riddle, with `:category` and `:season` loaded. Pass
  `preload: [...]` to load other associations instead.

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
      Schedule.save(riddle, attrs)
    end
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
      Schedule.delete(riddle)
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
  @spec change_riddle(Riddle.t(), map()) :: Ecto.Changeset.t()
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
  @spec record_first_solver(integer(), integer(), non_neg_integer() | nil) ::
          {:ok, :recorded | :already_set}
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
  one. Pass `force: true` to load them again over what the riddle already holds.
  """
  @spec preload_riddle(Riddle.t(), keyword()) :: Riddle.t()
  def preload_riddle(%Riddle{} = riddle, opts \\ []),
    do: Repo.preload(riddle, @riddle_preload, opts)

  @doc """
  Returns the list of categories.

  ## Examples

      iex> list_categories()
      [%Category{}, ...]

  """
  @spec list_categories() :: [Category.t()]
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
  @spec get_category!(integer() | String.t()) :: Category.t()
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
  @spec change_category(Category.t(), map()) :: Ecto.Changeset.t()
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  @doc "Returns every season with its `riddle_count`, latest start first."
  @spec list_seasons() :: [Season.t()]
  def list_seasons do
    from(s in Season,
      left_join: r in assoc(s, :riddles),
      group_by: s.id,
      order_by: [desc: s.starts_at],
      select_merge: %{riddle_count: count(r.id)}
    )
    |> Repo.all()
    |> Enum.map(&Season.with_days/1)
  end

  @doc """
  The seasons a riddle may join: the current season, if any, then the
  upcoming seasons, soonest first.
  """
  @spec list_current_and_upcoming_seasons() :: [Season.t()]
  def list_current_and_upcoming_seasons do
    now = Riddlr.Clock.utc_now()

    from(s in Season, where: s.ends_at > ^now, order_by: [asc: s.starts_at])
    |> Repo.all()
    |> Enum.map(&Season.with_days/1)
  end

  @doc """
  The season a new riddle starts in, picked from `seasons` (as
  `list_current_and_upcoming_seasons/0` returns them): the one holding
  `live_date`, or else the first. Returns nil when `seasons` is empty.
  """
  @spec default_season([Season.t()], DateTime.t() | nil) :: Season.t() | nil
  def default_season(seasons, live_date) do
    Enum.find(seasons, List.first(seasons), &(live_date && Season.holds?(&1, live_date)))
  end

  @doc """
  Gets a single season. Raises `Ecto.NoResultsError` if it does not exist.
  """
  @spec get_season!(integer() | String.t()) :: Season.t()
  def get_season!(id), do: Season |> Repo.get!(id) |> Season.with_days()

  @doc """
  Creates a season. Returns `{:ok, season}`, `{:error, changeset}` or
  `{:error, :unauthorized}`.
  """
  @spec create_season(Scope.t(), map()) ::
          {:ok, Season.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def create_season(%Scope{} = scope, attrs) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      %Season{}
      |> Season.changeset(attrs, Riddlr.Clock.utc_now())
      |> Repo.insert()
      |> name_overlapping_season()
    end
  end

  @doc """
  Updates a season. Returns `{:ok, season}`, `{:error, changeset}` or
  `{:error, :unauthorized}`.
  """
  @spec update_season(Scope.t(), Season.t(), map()) ::
          {:ok, Season.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def update_season(%Scope{} = scope, %Season{} = season, attrs) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      season
      |> Season.changeset(attrs, Riddlr.Clock.utc_now())
      |> Repo.update()
      |> name_overlapping_season()
    end
  end

  @doc """
  Deletes a season. A season that still has riddles is refused with an error
  on `:riddles`. Returns `{:ok, season}`, `{:error, changeset}` or
  `{:error, :unauthorized}`.
  """
  @spec delete_season(Scope.t(), Season.t()) ::
          {:ok, Season.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def delete_season(%Scope{} = scope, %Season{} = season) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      season
      |> Season.delete_changeset()
      |> Repo.delete()
    end
  end

  # The exclusion constraint refuses an overlap but cannot say with which
  # season. Look the clash up after the fact, so the error can name it.
  @spec name_overlapping_season({:ok, Season.t()} | {:error, Ecto.Changeset.t()}) ::
          {:ok, Season.t()} | {:error, Ecto.Changeset.t()}
  defp name_overlapping_season({:error, %Ecto.Changeset{errors: errors} = changeset} = error) do
    with index when is_integer(index) <- Enum.find_index(errors, &overlap_error?/1),
         %Season{} = clash <- find_clash(changeset) do
      clash = Season.with_days(clash)

      message =
        {"overlaps %{season} (%{starts_on} to %{ends_on})",
         constraint: :exclusion,
         season: clash.name,
         starts_on: Date.to_iso8601(clash.starts_on),
         ends_on: Date.to_iso8601(clash.ends_on)}

      {:error, %{changeset | errors: List.replace_at(errors, index, {:ends_on, message})}}
    else
      _ -> error
    end
  end

  defp name_overlapping_season(result), do: result

  @spec overlap_error?({atom(), {String.t(), keyword()}}) :: boolean()
  defp overlap_error?({:ends_on, {_message, opts}}), do: opts[:constraint] == :exclusion
  defp overlap_error?(_error), do: false

  @spec find_clash(Ecto.Changeset.t()) :: Season.t() | nil
  defp find_clash(changeset) do
    id = changeset.data.id
    starts_at = Ecto.Changeset.get_field(changeset, :starts_at)
    ends_at = Ecto.Changeset.get_field(changeset, :ends_at)

    Season
    |> where(
      [s],
      fragment(
        "tsrange(?, ?, '[)') && tsrange(?, ?, '[)')",
        s.starts_at,
        s.ends_at,
        type(^starts_at, :utc_datetime),
        type(^ends_at, :utc_datetime)
      )
    )
    |> then(fn query -> if id, do: where(query, [s], s.id != ^id), else: query end)
    |> order_by(:starts_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  The season's status now: `:upcoming`, `:current` or `:past`.
  """
  @spec season_status(Season.t()) :: Season.status()
  def season_status(%Season{} = season), do: Season.status(season, Riddlr.Clock.utc_now())

  @doc """
  The day fields an edit may not change now. See
  `Riddlr.Games.Season.locked_dates/2`.
  """
  @spec season_locked_dates(Season.t()) :: [:starts_on | :ends_on]
  def season_locked_dates(%Season{} = season),
    do: Season.locked_dates(season, Riddlr.Clock.utc_now())

  @doc "Returns a blank season for a new-season form."
  @spec new_season() :: Season.t()
  def new_season, do: %Season{}

  @doc "Returns an `%Ecto.Changeset{}` for tracking season changes."
  @spec change_season(Season.t(), map()) :: Ecto.Changeset.t()
  def change_season(%Season{} = season, attrs \\ %{}) do
    Season.changeset(season, attrs, Riddlr.Clock.utc_now())
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
