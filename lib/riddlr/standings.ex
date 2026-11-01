defmodule Riddlr.Standings do
  @moduledoc """
  **Standings**: the overall ranking of players across riddles.

  Read-only. Every number comes from saved `solves`, so Standings change
  when a riddle completes, not during play. `Riddlr.Games.transition/3`
  calls `broadcast_changed/0` once that commits; `subscribe/0` listens.

  `list/2` returns the top 50 players on a board; `player_row/3` returns one
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

  Every row also carries the player's `solves` and `entries` (see
  `Riddlr.Gameplay.Entry`) over the window, for the solve rate.

  Deleted players (solves with a nil `user_id`) and banned or suspended
  players are left out. Admins show like anyone else.

  A window picks which riddles count. `:all_time` counts every riddle.
  `:month` counts riddles whose `live_date` falls in the current UTC
  calendar month, by `Riddlr.Clock`.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2, having: 3, subquery: 1, where: 3]

  alias Riddlr.Accounts.User
  alias Riddlr.Clock
  alias Riddlr.Gameplay.Entry
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Games.Riddle
  alias Riddlr.Repo

  @limit 50
  @topic "standings"
  @boards [:points, :wins, :podiums, :fastest]
  @windows [:all_time, :month]

  @typedoc "A board to rank by."
  @type board :: :points | :wins | :podiums | :fastest

  @typedoc "The span of riddles a board counts."
  @type window :: :all_time | :month

  @typedoc """
  One player's line on a board. The Points, Wins and Podiums boards carry
  `points`, `wins` and `podiums`. The Fastest board carries the best
  `solve_time_ms` and the riddle it came from.
  """
  @type row :: %{
          required(:rank) => pos_integer(),
          required(:user_id) => integer(),
          required(:username) => String.t(),
          required(:solves) => non_neg_integer(),
          required(:entries) => non_neg_integer(),
          optional(:points) => non_neg_integer(),
          optional(:wins) => non_neg_integer(),
          optional(:podiums) => non_neg_integer(),
          optional(:solve_time_ms) => non_neg_integer(),
          optional(:live_date) => DateTime.t() | nil,
          optional(:riddle_name) => String.t(),
          optional(:riddle_number) => pos_integer() | nil
        }

  @doc """
  The top #{@limit} players on `board` over `window`, best first.
  """
  @spec list(board(), window()) :: [row()]
  def list(board, window) when board in @boards and window in @windows do
    from(row in subquery(ranked(board, window)),
      order_by: [asc: row.rank, asc: row.username],
      limit: @limit
    )
    |> Repo.all()
    |> add_rate(window)
  end

  @doc """
  The player's row on `board` over `window`, with the rank `list/2` would
  give them with no limit, or nil when they are not on the board.
  """
  @spec player_row(integer(), board(), window()) :: row() | nil
  def player_row(user_id, board, window) when board in @boards and window in @windows do
    from(row in subquery(ranked(board, window)), where: row.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      row -> [row] |> add_rate(window) |> hd()
    end
  end

  @doc """
  Subscribes the caller to Standings changes. Subscribers get
  `:standings_changed` after a riddle completes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Riddlr.PubSub, @topic)

  @doc """
  Tells subscribers the Standings changed. Call it only after the
  completion transaction commits, so no one reloads before the Solves are
  there.
  """
  @spec broadcast_changed() :: :ok | {:error, term()}
  def broadcast_changed, do: Phoenix.PubSub.broadcast(Riddlr.PubSub, @topic, :standings_changed)

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

  # Fastest: each player's single best solve. DISTINCT ON keeps the first
  # row per player, so the sort picks the lowest time, then the earlier
  # riddle.
  @spec board_query(board(), window()) :: Ecto.Query.t()
  defp board_query(:fastest, window) do
    from(s in Solve,
      as: :solve,
      join: r in Riddle,
      as: :riddle,
      on: r.id == s.riddle_id,
      join: u in User,
      as: :user,
      on: u.id == s.user_id,
      where: u.account_status not in [:banned, :suspended],
      where: not is_nil(s.solve_time_ms),
      distinct: s.user_id,
      order_by: [asc: s.solve_time_ms, asc: r.live_date],
      select: %{
        user_id: u.id,
        username: u.username,
        solve_time_ms: s.solve_time_ms,
        live_date: r.live_date,
        riddle_name: r.name,
        riddle_number: r.number
      }
    )
    |> in_window(window)
  end

  defp board_query(board, window) do
    from(s in Solve,
      as: :solve,
      join: r in Riddle,
      as: :riddle,
      on: r.id == s.riddle_id,
      join: u in User,
      as: :user,
      on: u.id == s.user_id,
      where: u.account_status not in [:banned, :suspended],
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

  # Solves and entries for the listed players, both over the window, so the
  # page can show the solve rate on any board.
  @spec add_rate([map()], window()) :: [row()]
  defp add_rate([], _window), do: []

  defp add_rate(rows, window) do
    ids = Enum.map(rows, & &1.user_id)
    solves = count_by_user(Solve, ids, window)
    entries = count_by_user(Entry, ids, window)

    Enum.map(rows, fn row ->
      Map.merge(row, %{
        solves: Map.get(solves, row.user_id, 0),
        entries: Map.get(entries, row.user_id, 0)
      })
    end)
  end

  @spec count_by_user(module(), [integer()], window()) :: %{integer() => non_neg_integer()}
  defp count_by_user(schema, ids, window) do
    from(x in schema,
      join: r in Riddle,
      as: :riddle,
      on: r.id == x.riddle_id,
      where: x.user_id in ^ids,
      group_by: x.user_id,
      select: {x.user_id, count(x.id)}
    )
    |> in_window(window)
    |> Repo.all()
    |> Map.new()
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
