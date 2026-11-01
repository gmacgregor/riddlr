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

  Players level on all three share a rank (1, 2, 2, 4) and are listed by
  username A–Z. The Wins and Podiums boards leave out players with none of
  their stat.

  Deleted players (solves with a nil `user_id`) and banned or suspended
  players are left out. Admins show like anyone else.

  A window picks which riddles count. `:all_time` counts every riddle.
  `:month` counts riddles whose `live_date` falls in the current UTC
  calendar month, by `Riddlr.Clock`.
  """

  import Ecto.Query, only: [dynamic: 1, dynamic: 2, from: 2, having: 3, order_by: 3, where: 3]

  alias Riddlr.Accounts.User
  alias Riddlr.Clock
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Games.Riddle
  alias Riddlr.Repo

  @limit 50

  @typedoc "A board to rank by."
  @type board :: :points | :wins | :podiums

  @typedoc "The span of riddles a board counts."
  @type window :: :all_time | :month

  @typedoc "One player's line on a board."
  @type row :: %{
          rank: pos_integer(),
          user_id: integer(),
          username: String.t(),
          points: non_neg_integer(),
          wins: non_neg_integer(),
          podiums: non_neg_integer()
        }

  @doc """
  The top #{@limit} players on `board` over `window`, best first.
  """
  @spec list(board(), window()) :: [row()]
  def list(board, window)
      when board in [:points, :wins, :podiums] and window in [:all_time, :month] do
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
      },
      limit: @limit
    )
    |> in_window(window)
    |> rank_by(board)
    |> Repo.all()
    |> add_ranks()
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

  # Rows arrive sorted. A row level with the one above on points, wins and
  # podiums takes its rank; any other row takes its place in the list.
  @spec add_ranks([map()]) :: [row()]
  defp add_ranks(rows) do
    rows
    |> Enum.with_index(1)
    |> Enum.map_reduce(nil, fn {row, place}, prev ->
      rank = if prev && score(prev) == score(row), do: prev.rank, else: place
      row = Map.put(row, :rank, rank)
      {row, row}
    end)
    |> elem(0)
  end

  @spec score(map()) :: {integer(), integer(), integer()}
  defp score(row), do: {row.points, row.wins, row.podiums}
end
