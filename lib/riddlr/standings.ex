defmodule Riddlr.Standings do
  @moduledoc """
  **Standings**: the overall ranking of players across riddles.

  Read-only. Every number comes from saved `solves`, so Standings change
  when a riddle completes, not during play.

  `list/2` returns the top 50 players on a board. Each board sorts by its
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
  calendar month, by `Riddlr.Clock`.
  """

  import Ecto.Query,
    only: [
      dynamic: 1,
      dynamic: 2,
      from: 2,
      having: 3,
      limit: 2,
      order_by: 3,
      subquery: 1,
      where: 3
    ]

  alias Riddlr.Accounts.User
  alias Riddlr.Clock
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Games.Riddle
  alias Riddlr.Repo

  @limit 50
  @boards [:points, :wins, :podiums, :fastest]

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
  def list(board, window) when board in @boards and window in [:all_time, :month] do
    board
    |> board_query(window)
    |> limit(@limit)
    |> Repo.all()
    |> add_ranks(board)
  end

  # Fastest: each player's single best solve. DISTINCT ON keeps the first
  # row per player, so the inner sort picks the lowest time, then the
  # earlier riddle.
  @spec board_query(board(), window()) :: Ecto.Query.t()
  defp board_query(:fastest, window) do
    best =
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

    from(b in subquery(best),
      order_by: [asc: b.solve_time_ms, asc: b.live_date, asc: b.username]
    )
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
        points: s.points |> sum() |> type(:integer) |> selected_as(:points),
        wins: s.id |> count() |> filter(s.placement == 1) |> selected_as(:wins),
        podiums: s.id |> count() |> filter(s.placement <= 3) |> selected_as(:podiums)
      }
    )
    |> in_window(window)
    |> rank_by(board)
  end

  # Sort by the board's own stat, then the other two, then username.
  @spec rank_by(Ecto.Query.t(), board()) :: Ecto.Query.t()
  defp rank_by(query, board) do
    stats = Enum.map(sort_keys(board), &{:desc, dynamic(selected_as(^&1))})
    name = [asc: dynamic([user: u], u.username)]

    query
    |> order_by([], ^(stats ++ name))
    |> with_some(board)
  end

  @spec sort_keys(board()) :: [:points | :wins | :podiums]
  defp sort_keys(:points), do: [:points, :wins, :podiums]
  defp sort_keys(:wins), do: [:wins, :podiums, :points]
  defp sort_keys(:podiums), do: [:podiums, :wins, :points]

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

  # Rows arrive sorted. A row level with the one above on the board's score
  # takes its rank; any other row takes its place in the list.
  @spec add_ranks([map()], board()) :: [row()]
  defp add_ranks(rows, board) do
    rows
    |> Enum.with_index(1)
    |> Enum.map_reduce(nil, fn {row, place}, prev ->
      rank = if prev && score(prev, board) == score(row, board), do: prev.rank, else: place
      row = Map.put(row, :rank, rank)
      {row, row}
    end)
    |> elem(0)
  end

  # Fastest ties need the same time on the same Live date.
  @spec score(map(), board()) :: tuple()
  defp score(row, :fastest), do: {row.solve_time_ms, row.live_date}
  defp score(row, _board), do: {row.points, row.wins, row.podiums}
end
