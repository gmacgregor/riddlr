defmodule RiddlrWeb.StandingsYouLiveTest do
  use RiddlrWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  setup do
    riddle = riddle_fixture()

    # 51 players, best first; the 51st falls outside the top 50.
    players =
      for place <- 1..51 do
        user = user_fixture()
        solve_fixture(riddle, user, %{placement: place, points: 100 - place})
        user
      end

    %{players: players}
  end

  test "highlights a signed-in player's row in the top 50 and pins nothing", %{
    conn: conn,
    players: players
  } do
    me = Enum.at(players, 2)
    {:ok, live, _html} = conn |> log_in_user(me) |> live(~p"/standings")

    assert has_element?(live, "#standings-#{me.id}[aria-current=true]")
    refute has_element?(live, "#standings-you")
  end

  test "pins a signed-in player's row below the list with its true rank", %{
    conn: conn,
    players: players
  } do
    me = List.last(players)
    {:ok, live, _html} = conn |> log_in_user(me) |> live(~p"/standings")

    refute has_element?(live, "#standings-#{me.id}")
    assert has_element?(live, "#standings-you[aria-current=true] .rg-stand__rank", "51")
    assert has_element?(live, "#standings-you .rg-stand__name", me.username)
  end

  test "no pinned row for a signed-out visitor", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    refute has_element?(live, "#standings-you")
    refute has_element?(live, "#standings-rows [aria-current]")
  end

  test "no pinned row for a signed-in player with no solves", %{conn: conn} do
    {:ok, live, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/standings")

    refute has_element?(live, "#standings-you")
  end
end
