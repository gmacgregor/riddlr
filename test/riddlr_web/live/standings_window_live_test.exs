defmodule RiddlrWeb.StandingsWindowLiveTest do
  # Freezes the clock, which is global, so not async.
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Clock.Frozen

  # Carl won last season, Bob earlier this season and Ann this month.
  setup do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])

    last = season_fixture(%{starts_on: ~D[2026-09-01], ends_on: ~D[2026-09-30]})
    current = season_fixture(%{starts_on: ~D[2026-10-01], ends_on: ~D[2026-12-31]})

    this_month = riddle_in_season_fixture(current, ~U[2026-11-02 12:00:00Z], current)
    last_month = riddle_in_season_fixture(current, ~U[2026-10-02 12:00:00Z], current)
    last_season = riddle_in_season_fixture(last, ~U[2026-09-02 12:00:00Z], current)

    ann = user_fixture(%{username: "ann"})
    bob = user_fixture(%{username: "bob"})
    carl = user_fixture(%{username: "carl"})

    solve_fixture(this_month, ann, %{placement: 1, points: 10})
    solve_fixture(last_month, bob, %{placement: 1, points: 10})
    solve_fixture(last_season, carl, %{placement: 1, points: 10})

    %{ann: ann, bob: bob, carl: carl}
  end

  test "opens on this season", %{conn: conn, ann: ann, bob: bob, carl: carl} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-window-season[aria-current]")
    assert has_element?(live, "#standings-#{ann.id}")
    assert has_element?(live, "#standings-#{bob.id}")
    refute has_element?(live, "#standings-#{carl.id}")
  end

  test "?window=month lists only this month's solvers", %{conn: conn, ann: ann, bob: bob} do
    {:ok, live, _html} = live(conn, ~p"/standings?window=month")

    assert has_element?(live, "#standings-#{ann.id}")
    refute has_element?(live, "#standings-#{bob.id}")
  end

  test "?window=all_time lists every solver", %{conn: conn, ann: ann, bob: bob, carl: carl} do
    {:ok, live, _html} = live(conn, ~p"/standings?window=all_time")

    for user <- [ann, bob, carl], do: assert(has_element?(live, "#standings-#{user.id}"))
  end

  test "a bad window falls back to this season", %{conn: conn, carl: carl} do
    {:ok, live, _html} = live(conn, ~p"/standings?window=bogus")

    assert has_element?(live, "#standings-window-season[aria-current]")
    refute has_element?(live, "#standings-#{carl.id}")
  end

  test "the switch moves between windows", %{conn: conn, bob: bob, carl: carl} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    live |> element("#standings-window-month") |> render_click()
    assert_patch(live, ~p"/standings?board=points&window=month")
    assert has_element?(live, "#standings-window-month[aria-current]")
    refute has_element?(live, "#standings-#{bob.id}")

    live |> element("#standings-window-all_time") |> render_click()
    assert_patch(live, ~p"/standings?board=points&window=all_time")
    assert has_element?(live, "#standings-#{carl.id}")

    live |> element("#standings-window-season") |> render_click()
    assert_patch(live, ~p"/standings?board=points&window=season")
    assert has_element?(live, "#standings-#{bob.id}")
    refute has_element?(live, "#standings-#{carl.id}")
  end

  test "every board works under this season", %{conn: conn, carl: carl} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    for board <- ~w(points wins podiums fastest) do
      live |> element("#standings-board-#{board}") |> render_click()
      assert_patch(live, ~p"/standings?board=#{board}&window=season")
      assert has_element?(live, "#standings-board")
      refute has_element?(live, "#standings-#{carl.id}")
    end
  end

  test "the season empty note shows when nobody has solved this season", %{conn: conn} do
    season_fixture(%{starts_on: ~D[2027-01-01], ends_on: ~D[2027-01-31]})
    Frozen.freeze(~U[2027-01-15 12:00:00Z])

    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(
             live,
             "#standings-empty",
             RiddlrWeb.GameCopy.Standings.standings_empty(:season)
           )

    refute has_element?(live, "#standings-board")
  end

  test "the month empty note shows when nobody has solved this month", %{conn: conn} do
    Frozen.freeze(~U[2027-01-15 12:00:00Z])

    {:ok, live, _html} = live(conn, ~p"/standings?window=month")

    assert has_element?(
             live,
             "#standings-empty",
             RiddlrWeb.GameCopy.Standings.standings_empty(:month)
           )

    refute has_element?(live, "#standings-board")
  end
end
