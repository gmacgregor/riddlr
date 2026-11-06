defmodule RiddlrWeb.StandingsSeasonLiveTest do
  # Freezes the clock, which is global, so not async.
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Clock.Frozen

  # Carl won the summer season, Bob the autumn one. Winter has not started.
  setup do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])

    summer = season_fixture(%{starts_on: ~D[2026-09-01], ends_on: ~D[2026-09-30]})
    autumn = season_fixture(%{starts_on: ~D[2026-10-01], ends_on: ~D[2026-12-31]})
    winter = season_fixture(%{starts_on: ~D[2027-02-01], ends_on: ~D[2027-02-28]})

    in_summer = riddle_in_season_fixture(summer, ~U[2026-09-02 12:00:00Z], autumn)
    in_autumn = riddle_in_season_fixture(autumn, ~U[2026-10-02 12:00:00Z], autumn)

    bob = user_fixture(%{username: "bob"})
    carl = user_fixture(%{username: "carl"})

    solve_fixture(in_summer, carl, %{placement: 1, points: 10})
    solve_fixture(in_autumn, bob, %{placement: 1, points: 10})

    %{summer: summer, autumn: autumn, winter: winter, bob: bob, carl: carl}
  end

  test "between seasons, This season shows the last one, labelled past",
       %{conn: conn, bob: bob, carl: carl} do
    Frozen.freeze(~U[2027-01-15 12:00:00Z])

    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-#{bob.id}")
    refute has_element?(live, "#standings-#{carl.id}")
    assert has_element?(live, "#standings-season-past")
  end

  test "the current season is not labelled past", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    refute has_element?(live, "#standings-season-past")
  end

  test "before any season has started, This season shows a No season yet note", %{conn: conn} do
    Frozen.freeze(~U[2026-08-15 12:00:00Z])

    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-no-season")
    refute has_element?(live, "#standings-board")
    refute has_element?(live, "#standings-empty")
  end

  test "the picker lists started seasons newest first, no upcoming ones",
       %{conn: conn, summer: summer, autumn: autumn, winter: winter} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    html = live |> element("#standings-season-picker select") |> render()
    ids = Regex.scan(~r/<option[^>]*value="(\d+)"/, html, capture: :all_but_first)

    assert List.flatten(ids) == [to_string(autumn.id), to_string(summer.id)]
    refute html =~ winter.name
  end

  test "the picker hides with only one started season", %{conn: conn} do
    Frozen.freeze(~U[2026-09-15 12:00:00Z])

    {:ok, live, _html} = live(conn, ~p"/standings")

    assert has_element?(live, "#standings-board")
    refute has_element?(live, "#standings-season-picker")
  end

  test "the picker shows only under This season", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/standings?window=month")

    refute has_element?(live, "#standings-season-picker")
  end

  test "choosing a season patches the URL and shows its board",
       %{conn: conn, summer: summer, bob: bob, carl: carl} do
    {:ok, live, _html} = live(conn, ~p"/standings")

    live
    |> form("#standings-season-picker", %{season: summer.id})
    |> render_change()

    assert_patch(live, ~p"/standings?board=points&season=#{summer.id}&window=season")
    assert has_element?(live, "#standings-#{carl.id}")
    refute has_element?(live, "#standings-#{bob.id}")
    assert has_element?(live, "#standings-season-past")
    assert has_element?(live, ~s(#standings-season option[value="#{summer.id}"][selected]))
  end

  test "loading a season's URL shows its board, and the board switch keeps it",
       %{conn: conn, summer: summer, carl: carl} do
    {:ok, live, _html} = live(conn, ~p"/standings?window=season&season=#{summer.id}")

    assert has_element?(live, "#standings-#{carl.id}")

    live |> element("#standings-board-wins") |> render_click()
    assert_patch(live, ~p"/standings?board=wins&season=#{summer.id}&window=season")
    assert has_element?(live, "#standings-#{carl.id}")
  end

  test "an unknown or upcoming season id falls back to This season",
       %{conn: conn, winter: winter, bob: bob, carl: carl} do
    for id <- [winter.id, -1, "bogus"] do
      {:ok, live, _html} = live(conn, ~p"/standings?window=season&season=#{id}")

      assert has_element?(live, "#standings-#{bob.id}"), "season #{id}"
      refute has_element?(live, "#standings-#{carl.id}"), "season #{id}"
    end
  end

  test "a Past season pins the player's own row",
       %{conn: conn, summer: summer, autumn: autumn} do
    in_summer = riddle_in_season_fixture(summer, ~U[2026-09-03 12:00:00Z], autumn)

    # 50 players ahead of me push my row out of the top 50.
    for place <- 1..50 do
      solve_fixture(in_summer, user_fixture(), %{placement: place, points: 100 - place})
    end

    me = user_fixture()
    solve_fixture(in_summer, me, %{placement: 51, points: 0})

    {:ok, live, _html} =
      conn
      |> log_in_user(me)
      |> live(~p"/standings?window=season&season=#{summer.id}")

    refute has_element?(live, "#standings-#{me.id}")
    assert has_element?(live, "#standings-you[aria-current=true] .rg-stand__rank", "52")
  end
end
