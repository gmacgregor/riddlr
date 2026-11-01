defmodule RiddlrWeb.StandingsLiveTest do
  use RiddlrWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  test "a signed-out visitor sees the empty state when nobody has solved", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-empty")
    refute has_element?(live, "#standings-board")
  end

  test "lists players by rank with points, wins and podiums", %{conn: conn} do
    [r1, r2] = for _ <- 1..2, do: riddle_fixture()
    ann = user_fixture(%{username: "ann"})
    bob = user_fixture(%{username: "bob"})

    solve_fixture(r1, ann, %{placement: 1, points: 10})
    solve_fixture(r2, ann, %{placement: 2, points: 9})
    solve_fixture(r1, bob, %{placement: 2, points: 9})

    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-#{ann.id} .rg-stand__rank", "1")
    assert has_element?(live, "#standings-#{ann.id} .rg-stand__name", "ann")
    assert has_element?(live, "#standings-#{ann.id} .rg-stand__pts", "19")
    assert has_element?(live, "#standings-#{ann.id} .rg-stand__wins", "1")
    assert has_element?(live, "#standings-#{ann.id} .rg-stand__pods", "2")
    assert has_element?(live, "#standings-#{bob.id} .rg-stand__rank", "2")
    refute has_element?(live, "#standings-empty")
  end

  test "the Fastest board links each riddle to its Results", %{conn: conn} do
    riddle = riddle_fixture()
    ann = user_fixture(%{username: "ann"})
    solve_fixture(riddle, ann, %{placement: 1, solve_time_ms: 2_500})

    {:ok, live, _html} = live(conn, ~p"/standings?board=fastest")

    assert has_element?(
             live,
             ~s(#standings-#{ann.id} .rg-stand__riddle a[href="/game/#{riddle.id}/results"])
           )
  end

  test "explains how each board is counted", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-how summary", "How are these counted?")

    for board <- ~w(points wins podiums fastest) do
      assert has_element?(live, "#standings-how-#{board} dd")
    end
  end
end
