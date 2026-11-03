defmodule RiddlrWeb.HomeSnapshotTest do
  # Turns on the node-wide cache and counts every query on the node.
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.CacheHelpers

  alias Riddlr.{Cache, Games, GamesFixtures}

  setup :enable_cache

  # The fixtures write past Games, so nothing rebuilds the snapshot; start cold.
  setup do
    {:ok, practice} =
      Games.create_practice_riddle(GamesFixtures.system_scope(), %{
        description: "What am I?",
        answer: "echo"
      })

    next = upcoming("ready", ~U[2030-01-01 14:05:00Z])
    Cache.clear()
    %{next: next, practice: practice}
  end

  test "a warm mount, first render and connected, runs no query", %{conn: conn, next: next} do
    Games.home_snapshot()

    {queries, {:ok, live, _html}} = count_queries(fn -> live(conn, ~p"/") end)

    assert queries == 0
    assert has_element?(live, "#hero-card a.rg-btn[href='/game/#{next.id}/lobby']")
  end

  test "views reloading on a broadcast run no query", %{conn: conn} do
    views = for _ <- 1..5, do: elem(live(conn, ~p"/"), 1)
    other = GamesFixtures.riddle_fixture()

    {queries, _} =
      count_queries(fn ->
        for view <- views do
          send(view.pid, {:riddle_saved, other})
          render(view)
        end
      end)

    assert queries == 0
  end

  test "a transition rebuilds the snapshot before it broadcasts", %{next: next} do
    Games.home_snapshot()
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:live")

    {:ok, _} = Games.transition(next.id, :live)

    assert_receive {:riddle_live, _}
    assert {:ok, %{next: %{id: id, play_status: "live"}}} = Cache.get(:home)
    assert id == next.id
  end

  test "a practice riddle change rebuilds the snapshot", %{practice: practice} do
    Games.home_snapshot()

    {:ok, _} =
      Games.update_practice_riddle(GamesFixtures.system_scope(), practice, %{answer: "shadow"})

    assert {:ok, %{practice: [%{answer: "shadow"}]}} = Cache.get(:home)
  end

  defp upcoming(play_status, live_date) do
    GamesFixtures.riddle_fixture()
    |> Ecto.Changeset.change(
      play_status: play_status,
      publish_status: "published",
      live_date: live_date
    )
    |> Riddlr.Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end
end
