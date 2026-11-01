defmodule RiddlrWeb.StandingsBoardLiveTest do
  use RiddlrWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  setup do
    [r1, r2, r3] = for _ <- 1..3, do: riddle_fixture()

    # On points: dan (21), then ann (19). On wins: ann only.
    ann = user_fixture(%{username: "ann"})
    dan = user_fixture(%{username: "dan"})

    solve_fixture(r1, ann, %{placement: 1, points: 10})
    solve_fixture(r2, ann, %{placement: 2, points: 9})
    for r <- [r1, r2, r3], do: solve_fixture(r, dan, %{placement: 4, points: 7})

    %{ann: ann, dan: dan}
  end

  test "?board=wins ranks by wins and hides players with none", %{
    conn: conn,
    ann: ann,
    dan: dan
  } do
    {:ok, live, _html} = live(conn, ~p"/standings?board=wins")

    assert has_element?(live, "#standings-#{ann.id} .rg-stand__rank", "1")
    refute has_element?(live, "#standings-#{dan.id}")
    assert has_element?(live, "#standings-board-wins[aria-current]")
    assert has_element?(live, "th.rg-stand__wins[aria-sort=descending]")
  end

  test "a bad board falls back to points", %{conn: conn, ann: ann, dan: dan} do
    {:ok, live, _html} = live(conn, ~p"/standings?board=bogus")

    assert has_element?(live, "#standings-#{dan.id} .rg-stand__rank", "1")
    assert has_element?(live, "#standings-#{ann.id} .rg-stand__rank", "2")
    assert has_element?(live, "#standings-board-points[aria-current]")
  end

  test "board tabs and window switch keep each other's choice", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    live |> element("#standings-board-podiums") |> render_click()
    assert_patch(live, ~p"/standings?board=podiums&window=all_time")

    live |> element("#standings-window-month") |> render_click()
    assert_patch(live, ~p"/standings?board=podiums&window=month")
    assert has_element?(live, "#standings-board-podiums[aria-current]")
  end
end
