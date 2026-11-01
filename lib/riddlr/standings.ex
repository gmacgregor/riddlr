defmodule Riddlr.Standings do
  @moduledoc """
  **Standings**: the overall ranking of players across riddles.

  Read-only. Every number comes from saved `solves`, so Standings change
  when a riddle completes, not during play.

  `list/2` returns the top 50 players on a board. The Points board sorts
  by points, then wins, then podiums. Players level on all three share a
  rank (1, 2, 2, 4) and are listed by username A–Z.

  Deleted players (solves with a nil `user_id`) and banned or suspended
  players are left out. Admins show like anyone else.
  """

  import Ecto.Query, only: [from: 2]

  alias Riddlr.Accounts.User
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Repo

  @limit 50

  @typedoc "A board to rank by."
  @type board :: :points

  @typedoc "The span of riddles a board counts."
  @type window :: :all_time

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
  def list(:points, :all_time) do
    from(s in Solve,
      join: u in User,
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
      order_by: [
        desc: selected_as(:points),
        desc: selected_as(:wins),
        desc: selected_as(:podiums),
        asc: u.username
      ],
      limit: @limit
    )
    |> Repo.all()
    |> add_ranks()
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
