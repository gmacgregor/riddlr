defmodule Riddlr.StandingsCacheTest do
  # Turns on the node-wide cache, counts every query and freezes the clock.
  use Riddlr.DataCase, async: false

  import Riddlr.AccountsFixtures
  import Riddlr.CacheHelpers
  import Riddlr.GamesFixtures

  alias Riddlr.Accounts
  alias Riddlr.Clock.Frozen
  alias Riddlr.Standings

  setup :enable_cache

  setup do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])
    ann = user_fixture(%{username: "ann"})
    riddle = riddle_fixture() |> went_live(~U[2026-11-02 12:00:00Z])
    solve_fixture(riddle, ann, %{placement: 1, points: 10})
    %{ann: ann, riddle: riddle}
  end

  test "after a change, every top list reads with no query", %{ann: ann} do
    Standings.broadcast_changed()

    {queries, results} =
      count_queries(fn ->
        for board <- [:points, :wins, :podiums, :fastest], window <- [:all_time, :month] do
          Standings.list(board, window)
        end
      end)

    assert queries == 0
    assert Enum.all?(results, &match?([%{user_id: id}] when id == ann.id, &1))
  end

  test "a player's row is read once, then cached, absent rows included", %{ann: ann} do
    assert {1, %{rank: 1}} =
             count_queries(fn -> Standings.player_row(ann.id, :points, :all_time) end)

    assert {0, %{rank: 1}} =
             count_queries(fn -> Standings.player_row(ann.id, :points, :all_time) end)

    assert {1, nil} = count_queries(fn -> Standings.player_row(-1, :points, :all_time) end)
    assert {0, nil} = count_queries(fn -> Standings.player_row(-1, :points, :all_time) end)
  end

  test "a completion's refresh shows new solves", %{riddle: riddle} do
    assert [_ann] = Standings.list(:points, :all_time)

    solve_fixture(riddle, user_fixture(%{username: "bob"}), %{placement: 2, points: 9})
    assert [_ann] = Standings.list(:points, :all_time)

    Standings.broadcast_changed()
    assert [%{username: "ann"}, %{username: "bob"}] = Standings.list(:points, :all_time)
  end

  test "a ban drops the player from cached boards and rows", %{ann: ann} do
    assert [_ann] = Standings.list(:points, :all_time)
    assert %{rank: 1} = Standings.player_row(ann.id, :points, :all_time)

    {:ok, _} = Accounts.set_user_status(ann, :banned)

    assert Standings.list(:points, :all_time) == []
    assert Standings.player_row(ann.id, :points, :all_time) == nil
  end

  test "a new month reads afresh", %{ann: ann} do
    assert [%{user_id: id}] = Standings.list(:points, :month)
    assert id == ann.id

    Frozen.freeze(~U[2026-12-01 00:00:00Z])

    assert Standings.list(:points, :month) == []
  end

  defp went_live(riddle, at) do
    riddle |> Ecto.Changeset.change(live_date: at) |> Riddlr.Repo.update!()
  end
end
