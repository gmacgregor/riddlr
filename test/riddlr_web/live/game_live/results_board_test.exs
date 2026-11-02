defmodule RiddlrWeb.GameLive.ResultsBoardTest do
  # Turns on the node-wide cache and counts every query on the node.
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.CacheHelpers

  alias Riddlr.{AccountsFixtures, Cache, Gameplay, Games, GamesFixtures, Repo}
  alias Riddlr.Gameplay.Solve

  setup :enable_cache

  test "a warm mount runs the same queries for 5 solvers as for 500", %{conn: conn} do
    small = completed_riddle(solvers: 5)
    large = completed_riddle(solvers: 500)

    {small_queries, _} = count_queries(fn -> {:ok, _, _} = live(conn, path(small)) end)
    {large_queries, _} = count_queries(fn -> {:ok, _, _} = live(conn, path(large)) end)

    assert small_queries == large_queries
  end

  test "a warm mount never reads the solves table", %{conn: conn} do
    riddle = completed_riddle(solvers: 60)

    {sources, _} = query_sources(fn -> {:ok, _, _} = live(conn, path(riddle)) end)

    refute "solves" in sources
  end

  test "shows the first 50 solvers and the total", %{conn: conn} do
    riddle = completed_riddle(solvers: 60)

    {:ok, live, _html} = live(conn, path(riddle))

    assert live
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(".rg-board .rg-row")
           |> Enum.count() == 50

    assert has_element?(live, "#res-by", RiddlrWeb.GameCopy.solved_count(60))
  end

  test "a viewer placed below the board sees their own row under it", %{conn: conn} do
    riddle = completed_riddle(solvers: 60)
    user = AccountsFixtures.user_fixture()
    insert_solves(riddle, [{user.id, 61}])
    Gameplay.warm_board(riddle.id)

    {:ok, live, _html} = conn |> log_in_user(user) |> live(path(riddle))

    assert has_element?(live, "#board-me.is-me .rg-row__place", "61")
    assert has_element?(live, "#res-you .rg-stamp", "61ST")
  end

  test "a viewer on the board gets no second row", %{conn: conn} do
    riddle = completed_riddle(solvers: 3)
    user = AccountsFixtures.user_fixture()
    insert_solves(riddle, [{user.id, 4}])
    Gameplay.warm_board(riddle.id)

    {:ok, live, _html} = conn |> log_in_user(user) |> live(path(riddle))

    assert has_element?(live, ".rg-board .rg-row.is-me .rg-row__place", "4")
    refute has_element?(live, "#board-me")
  end

  test "completing a riddle caches its board before it broadcasts" do
    riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")

    {:ok, _} = Games.transition(riddle.id, :completed)

    assert_receive {:riddle_completed, _}
    assert {:ok, %{top: [], total: 0}} = Cache.get({:results, riddle.id})
  end

  test "archive drops the cached board and the page does not cache it again", %{conn: conn} do
    riddle = completed_riddle(solvers: 2)
    assert {:ok, _} = Cache.get({:results, riddle.id})

    {:ok, _} = Games.transition(riddle.id, :archived)
    assert Cache.get({:results, riddle.id}) == :error

    {:ok, live, _html} = live(conn, path(riddle))
    assert has_element?(live, ".rg-board .rg-row")
    assert Cache.get({:results, riddle.id}) == :error
  end

  test "a cold cache reads the board on the connected render", %{conn: conn} do
    riddle = completed_riddle(solvers: 2)
    Cache.clear()

    conn = get(conn, path(riddle))
    refute html_response(conn, 200) =~ ~s(id="res-by")

    {:ok, live, _html} = live(conn, path(riddle))
    assert has_element?(live, "#res-by")
    assert {:ok, %{total: 2}} = Cache.get({:results, riddle.id})
  end

  defp path(riddle), do: ~p"/game/#{riddle.id}/results"

  # A completed riddle whose solves belong to deleted accounts (nil user),
  # so hundreds cost no user fixtures. Its board is cached.
  defp completed_riddle(solvers: n) do
    riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
    insert_solves(riddle, Enum.map(1..n//1, &{nil, &1}))
    Gameplay.warm_board(riddle.id)
    riddle
  end

  defp insert_solves(riddle, rows) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      Solve,
      for {user_id, placement} <- rows do
        %{
          riddle_id: riddle.id,
          user_id: user_id,
          placement: placement,
          points: 0,
          solve_time_ms: placement * 1_000,
          inserted_at: now,
          updated_at: now
        }
      end
    )
  end

  defp set_play_status(riddle, status) do
    riddle
    |> Ecto.Changeset.change(play_status: status, publish_status: "published")
    |> Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end
end
