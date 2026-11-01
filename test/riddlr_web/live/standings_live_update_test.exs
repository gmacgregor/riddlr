defmodule RiddlrWeb.StandingsLiveUpdateTest do
  # The "standings" topic is global, so not async.
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Gameplay

  test "a viewer sees new results when a riddle completes, without reloading", %{conn: conn} do
    riddle =
      riddle_fixture(%{
        play_status: "live",
        publish_status: "published",
        live_date: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    ann = user_fixture(%{username: "ann"})

    {:ok, live, _html} = live(conn, ~p"/standings")
    assert has_element?(live, "#standings-empty")

    assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, ann, "keyboard")

    assert {:ok, _} =
             Riddlr.Games.transition(riddle.id, :completed, %{
               solves: Gameplay.solve_rows(riddle.id),
               entries: Gameplay.entry_rows(riddle.id)
             })

    assert has_element?(live, "#standings-#{ann.id} .rg-stand__pts", "10")
    refute has_element?(live, "#standings-empty")
  end

  test "a pinned row moves when a riddle completes", %{conn: conn} do
    done = riddle_fixture()

    for place <- 1..50 do
      solve_fixture(done, user_fixture(), %{placement: place, points: 100 - place})
    end

    me = user_fixture()
    solve_fixture(done, me, %{placement: 51, points: 0})

    {:ok, live, _html} = conn |> log_in_user(me) |> live(~p"/standings")
    assert has_element?(live, "#standings-you .rg-stand__rank", "51")

    riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})
    other = user_fixture()

    assert {:ok, _} =
             Riddlr.Games.transition(riddle.id, :completed, %{
               solves: [
                 %{riddle_id: riddle.id, user_id: other.id, placement: 1, points: 0}
                 |> Map.merge(%{inserted_at: now(), updated_at: now()})
               ]
             })

    assert has_element?(live, "#standings-you .rg-stand__rank", "52")
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
