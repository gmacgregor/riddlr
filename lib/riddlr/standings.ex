defmodule Riddlr.Standings do
  @moduledoc """
  **Standings**: the overall ranking of players across riddles.

  Read-only. Every number comes from saved `solves`, so Standings change
  when a riddle completes, not during play. `Riddlr.Games.transition/3`
  calls `broadcast_changed/0` once that commits; `subscribe/0` listens.

  Standings is a read model across contexts: it joins Gameplay's `solves`,
  Games' `riddles` and Accounts' `users` in one query, because a ranking
  built from three context calls would need far more round trips. It
  only reads these tables and never writes them. Writes stay with the
  owning context.

  `list/2` returns the top @limit players on a board; `player_row/3` returns one
  player's row with the same rank, wherever they place. Each board sorts by its
  own stat first, then the other two:

  - Points: points, wins, podiums
  - Wins: wins, podiums, points
  - Podiums: podiums, wins, points
  - Fastest: each player's best `solve_time_ms` on any solve, then the
    earlier riddle (by Live date)

  Players level on all three (on Fastest: same time, same Live date) share
  a rank (1, 2, 2, 4) and are listed by username A–Z. Solves with no time
  don't count on Fastest. The Wins and Podiums boards leave out players with none of
  their stat.

  Deleted players (solves with a nil `user_id`) and banned or suspended
  players are left out. Admins show like anyone else.

  A window picks which riddles count. `:all_time` counts every riddle.
  `:month` counts riddles whose `live_date` falls in the current UTC
  calendar month, by `Riddlr.Clock`. `{:season, id}` counts the riddles in
  that Season, by the riddle's Season link, not by date. `:season` means
  the current Season or, between Seasons, the one that ended most recently
  (`Riddlr.Games.latest_started_season/0`); before any Season has started
  it counts nothing. A Past season's riddle list is frozen, so its boards
  never change.

  Both reads are cached (`Riddlr.Cache`), keyed by board and window, with the
  month window keyed by year and month so a new month misses on its own.
  `:season` turns into `{:season, id}` before the cache lookup, so a new
  Season misses on its own too. `broadcast_changed/0` drops every entry and
  refills the top lists for all time, this month and This season
  before it tells subscribers, so they reload from a warm cache. A ban,
  suspension or unban drops every entry (`invalidate/0`), as does deleting a
  riddle. Other admin edits to a finished riddle (its name, its Live date)
  show after the next completion.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2, having: 3, subquery: 1, where: 3]

  alias Riddlr.Accounts.User
  alias Riddlr.Cache
  alias Riddlr.Clock
  alias Riddlr.Games
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Games.Riddle
  alias Riddlr.Repo

  @limit 50
  @topic "standings"
  @boards [:points, :wins, :podiums, :fastest]
  @windows [:all_time, :month, :season]

  # A window `list/2` and `player_row/3` take: a named one or a Season id.
  defguardp is_window(window)
            when window in @windows or
                   (is_tuple(window) and tuple_size(window) == 2 and
                      elem(window, 0) == :season and is_integer(elem(window, 1)))

  @typedoc "A board to rank by."
  @type board :: :points | :wins | :podiums | :fastest

  @typedoc """
  The span of riddles a board counts. `:season` is This season: the
  current Season or the one that ended most recently. `{:season, id}` is a
  given one.
  """
  @type window :: :all_time | :month | :season | {:season, integer()}

  # A window with `:season` turned into a Season id.
  @typep resolved :: :all_time | :month | {:season, integer()}

  @typedoc """
  One player's line on a board. The Points, Wins and Podiums boards carry
  `points`, `wins` and `podiums`. The Fastest board carries the best
  `solve_time_ms` and the riddle it came from.
  """
  @type row :: %{
          required(:rank) => pos_integer(),
          required(:user_id) => integer(),
          required(:username) => String.t(),
          optional(:points) => non_neg_integer(),
          optional(:wins) => non_neg_integer(),
          optional(:podiums) => non_neg_integer(),
          optional(:solve_time_ms) => non_neg_integer(),
          optional(:live_date) => DateTime.t() | nil,
          optional(:riddle_id) => integer(),
          optional(:riddle_name) => String.t(),
          optional(:riddle_number) => pos_integer() | nil
        }

  @doc """
  The top #{@limit} players on `board` over `window`, best first.
  """
  @spec list(board(), window()) :: [row()]
  def list(board, window) when board in @boards and is_window(window) do
    case resolve(window) do
      nil -> []
      window -> Cache.fetch(key(board, window, :top), fn -> list_query(board, window) end)
    end
  end

  @spec list_query(board(), window()) :: [row()]
  defp list_query(board, window) do
    from(row in subquery(ranked(board, window)),
      order_by: [asc: row.rank, asc: row.username],
      limit: @limit
    )
    |> Repo.all()
  end

  @doc """
  The player's row on `board` over `window`, with the rank `list/2` would
  give them with no limit, or nil when they are not on the board.
  """
  @spec player_row(integer(), board(), window()) :: row() | nil
  def player_row(user_id, board, window) when board in @boards and is_window(window) do
    case resolve(window) do
      nil ->
        nil

      window ->
        Cache.fetch(key(board, window, {:user, user_id}), fn ->
          from(row in subquery(ranked(board, window)), where: row.user_id == ^user_id)
          |> Repo.one()
        end)
    end
  end

  # Turns `:season` into `{:season, id}` for the latest started Season, or
  # nil before any Season has started. Other windows pass through.
  @spec resolve(window()) :: resolved() | nil
  defp resolve(:season) do
    case Games.latest_started_season() do
      nil -> nil
      season -> {:season, season.id}
    end
  end

  defp resolve(window), do: window

  @doc """
  Drops every cached board and player row. Call it when something outside a
  completion changes who is on a board, such as a ban.
  """
  @spec invalidate() :: :ok
  def invalidate, do: Cache.delete_match({:standings, :_, :_, :_})

  @spec key(board(), window(), :top | {:user, integer()}) :: tuple()
  defp key(board, window, part), do: {:standings, board, window_key(window), part}

  @spec window_key(resolved()) ::
          :all_time | {:month, {integer(), pos_integer()}} | {:season, integer()}
  defp window_key(:all_time), do: :all_time
  defp window_key({:season, _id} = window), do: window

  defp window_key(:month) do
    %{year: year, month: month} = Clock.utc_now()
    {:month, {year, month}}
  end

  @doc """
  Subscribes the caller to Standings changes. Subscribers get
  `:standings_changed` after a riddle completes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Riddlr.PubSub, @topic)

  @doc """
  Refills the cached top lists and tells subscribers the Standings changed.
  Call it only after the completion transaction commits, so no one reloads
  before the Solves are there.
  """
  @spec broadcast_changed() :: :ok | {:error, term()}
  def broadcast_changed do
    invalidate()

    windows = Enum.reject([:all_time, :month, resolve(:season)], &is_nil/1)

    for board <- @boards, window <- windows do
      Cache.put(key(board, window, :top), list_query(board, window))
    end

    Phoenix.PubSub.broadcast(Riddlr.PubSub, @topic, :standings_changed)
  end

  # Every player on the board with their rank. rank() gives players level on
  # every sort key the same rank and skips the places after them (1, 2, 2, 4).
  # Ranking must happen before any filter or limit, so callers wrap this in
  # a subquery.
  @spec ranked(board(), window()) :: Ecto.Query.t()
  defp ranked(board, window) do
    order = Enum.map(sort_keys(board), fn {dir, key} -> {dir, dynamic([b], field(b, ^key))} end)

    from(b in subquery(board_query(board, window)),
      select: merge(b, %{rank: over(rank(), :board)}),
      windows: [board: [order_by: ^order]]
    )
  end

  @spec sort_keys(board()) :: keyword(atom())
  defp sort_keys(:points), do: [desc: :points, desc: :wins, desc: :podiums]
  defp sort_keys(:wins), do: [desc: :wins, desc: :podiums, desc: :points]
  defp sort_keys(:podiums), do: [desc: :podiums, desc: :wins, desc: :points]
  defp sort_keys(:fastest), do: [asc: :solve_time_ms, asc: :live_date]

  # Solves that count on a board, joined to their riddle and player. Deleted
  # players drop out with the inner join; banned and suspended players are
  # left out.
  @spec counted_solves() :: Ecto.Query.t()
  defp counted_solves do
    from(s in Solve,
      as: :solve,
      join: r in Riddle,
      as: :riddle,
      on: r.id == s.riddle_id,
      join: u in User,
      as: :user,
      on: u.id == s.user_id,
      where: u.account_status not in [:banned, :suspended]
    )
  end

  # Fastest: each player's single best solve. DISTINCT ON keeps the first
  # row per player, so the sort picks the lowest time, then the earlier
  # riddle; the solve id makes the pick stable when both match.
  @spec board_query(board(), window()) :: Ecto.Query.t()
  defp board_query(:fastest, window) do
    from([solve: s, riddle: r, user: u] in counted_solves(),
      where: not is_nil(s.solve_time_ms),
      distinct: s.user_id,
      order_by: [asc: s.solve_time_ms, asc: r.live_date, asc: s.id],
      select: %{
        user_id: u.id,
        username: u.username,
        solve_time_ms: s.solve_time_ms,
        live_date: r.live_date,
        riddle_id: r.id,
        riddle_name: r.name,
        riddle_number: r.number
      }
    )
    |> in_window(window)
  end

  defp board_query(board, window) do
    from([solve: s, user: u] in counted_solves(),
      group_by: [u.id, u.username],
      select: %{
        user_id: u.id,
        username: u.username,
        points: s.points |> sum() |> type(:integer),
        wins: s.id |> count() |> filter(s.placement == 1),
        podiums: s.id |> count() |> filter(s.placement <= 3)
      }
    )
    |> in_window(window)
    |> with_some(board)
  end

  # The Wins and Podiums boards only list players with at least one.
  @spec with_some(Ecto.Query.t(), board()) :: Ecto.Query.t()
  defp with_some(query, :points), do: query

  defp with_some(query, :wins),
    do: having(query, [solve: s], count(s.id) |> filter(s.placement == 1) > 0)

  defp with_some(query, :podiums),
    do: having(query, [solve: s], count(s.id) |> filter(s.placement <= 3) > 0)

  @spec in_window(Ecto.Query.t(), window()) :: Ecto.Query.t()
  defp in_window(query, :all_time), do: query

  defp in_window(query, {:season, id}), do: where(query, [riddle: r], r.season_id == ^id)

  defp in_window(query, :month) do
    {from, to} = month_bounds(Clock.utc_now())
    where(query, [riddle: r], r.live_date >= ^from and r.live_date < ^to)
  end

  # Start of this month and start of next month, both UTC midnight.
  @spec month_bounds(DateTime.t()) :: {DateTime.t(), DateTime.t()}
  defp month_bounds(now) do
    first = Date.beginning_of_month(now)
    next = first |> Date.end_of_month() |> Date.add(1)
    {DateTime.new!(first, ~T[00:00:00]), DateTime.new!(next, ~T[00:00:00])}
  end
end
