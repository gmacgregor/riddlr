defmodule RiddlrWeb.StandingsWindowLiveTest do
  # Freezes the clock, which is global, so not async.
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Clock.Frozen

  defp went_live(riddle, at) do
    riddle |> Ecto.Changeset.change(live_date: at) |> Riddlr.Repo.update!()
  end

  setup do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])

    this_month = riddle_fixture() |> went_live(~U[2026-11-02 12:00:00Z])
    last_month = riddle_fixture() |> went_live(~U[2026-10-02 12:00:00Z])

    ann = user_fixture(%{username: "ann"})
    bob = user_fixture(%{username: "bob"})

    solve_fixture(this_month, ann, %{placement: 1, points: 10})
    solve_fixture(last_month, bob, %{placement: 1, points: 10})

    %{ann: ann, bob: bob}
  end

  test "?window=month lists only this month's solvers", %{conn: conn, ann: ann, bob: bob} do
    {:ok, live, _html} = live(conn, ~p"/standings?window=month")

    assert has_element?(live, "#standings-#{ann.id}")
    refute has_element?(live, "#standings-#{bob.id}")
  end

  test "a bad window falls back to all-time", %{conn: conn, ann: ann, bob: bob} do
    {:ok, live, _html} = live(conn, ~p"/standings?window=bogus")

    assert has_element?(live, "#standings-#{ann.id}")
    assert has_element?(live, "#standings-#{bob.id}")
    assert has_element?(live, "#standings-window-all_time[aria-current]")
  end

  test "the switch moves between windows", %{conn: conn, bob: bob} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-window-all_time[aria-current]")

    live |> element("#standings-window-month") |> render_click()
    assert_patch(live, ~p"/standings?board=points&window=month")
    assert has_element?(live, "#standings-window-month[aria-current]")
    refute has_element?(live, "#standings-#{bob.id}")

    live |> element("#standings-window-all_time") |> render_click()
    assert_patch(live, ~p"/standings?board=points&window=all_time")
    assert has_element?(live, "#standings-#{bob.id}")
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
