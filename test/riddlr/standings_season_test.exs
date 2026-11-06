defmodule Riddlr.StandingsSeasonTest do
  # Freezes the clock, which is global, so not async.
  use Riddlr.DataCase, async: false

  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Clock.Frozen
  alias Riddlr.Standings

  @boards [:points, :wins, :podiums, :fastest]

  setup do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])

    last = season_fixture(%{starts_on: ~D[2026-10-01], ends_on: ~D[2026-10-31]})
    current = season_fixture(%{starts_on: ~D[2026-11-01], ends_on: ~D[2026-12-31]})

    this_season = riddle_in_season_fixture(current, ~U[2026-11-02 12:00:00Z], current)
    last_season = riddle_in_season_fixture(last, ~U[2026-10-02 12:00:00Z], current)

    ann = user_fixture(%{username: "ann"})
    bob = user_fixture(%{username: "bob"})

    solve_fixture(this_season, ann, %{placement: 1, points: 10, solve_time_ms: 8_000})
    solve_fixture(last_season, bob, %{placement: 1, points: 10, solve_time_ms: 1_000})
    solve_fixture(last_season, ann, %{placement: 2, points: 9, solve_time_ms: 2_000})

    %{last: last, current: current, ann: ann, bob: bob}
  end

  describe ":season" do
    test "counts only riddles in the current season" do
      assert [%{username: "ann", points: 10, wins: 1, podiums: 1}] =
               Standings.list(:points, :season)
    end

    test "works on every board" do
      for board <- @boards do
        assert [%{username: "ann"}] = Standings.list(board, :season), "board #{board}"
      end

      assert [%{solve_time_ms: 8_000}] = Standings.list(:fastest, :season)
    end

    test "player_row ranks within the current season", %{ann: ann, bob: bob} do
      assert %{rank: 1, points: 10} = Standings.player_row(ann.id, :points, :season)
      assert Standings.player_row(bob.id, :points, :season) == nil
    end

    test "a new season starts everyone at zero" do
      season_fixture(%{starts_on: ~D[2027-01-01], ends_on: ~D[2027-01-31]})
      assert [_ann] = Standings.list(:points, :season)

      Frozen.freeze(~U[2027-01-15 12:00:00Z])

      assert Standings.list(:points, :season) == []
    end

    test "counts nothing when no season is current", %{ann: ann} do
      Frozen.freeze(~U[2027-03-01 12:00:00Z])

      assert Standings.list(:points, :season) == []
      assert Standings.player_row(ann.id, :points, :season) == nil
    end
  end

  describe "{:season, id}" do
    test "counts only riddles in that season", %{last: last, ann: ann} do
      assert [%{username: "bob", points: 10}, %{username: "ann", points: 9}] =
               Standings.list(:points, {:season, last.id})

      assert %{rank: 2} = Standings.player_row(ann.id, :points, {:season, last.id})
    end

    test "works on every board", %{last: last} do
      for board <- @boards do
        assert [%{username: "bob"} | _] = Standings.list(board, {:season, last.id}),
               "board #{board}"
      end
    end
  end
end
