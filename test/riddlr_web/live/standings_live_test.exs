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

  test "shows each player's solve rate on every board", %{conn: conn} do
    riddles = for _ <- 1..10, do: riddle_fixture()
    ann = user_fixture(%{username: "ann"})

    for r <- riddles, do: entry_fixture(r, ann)
    for r <- Enum.take(riddles, 7), do: solve_fixture(r, ann, %{placement: 1})

    for board <- ~w(points wins podiums fastest) do
      {:ok, live, _html} = live(conn, ~p"/standings?board=#{board}")
      assert has_element?(live, "#standings-#{ann.id} .rg-stand__rate", "7/10 · 70%")
    end
  end
end
