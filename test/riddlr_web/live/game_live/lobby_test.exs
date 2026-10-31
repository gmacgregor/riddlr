defmodule RiddlrWeb.GameLive.LobbyTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.Clock.Frozen
  alias Riddlr.{Games, GamesFixtures, AccountsFixtures}
  alias RiddlrWeb.GameComponents
  alias RiddlrWeb.GameCopy

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user}
  end

  describe "mount access control" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      riddle = GamesFixtures.riddle_fixture()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")
    end

    test "redirects to home when riddle does not exist", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/game/999999/lobby")
    end

    test "redirects when riddle is :closed", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture()
      assert riddle.play_status == "closed"

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == GameCopy.lobby_unavailable()
    end

    test "redirects when riddle is :scheduled", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == GameCopy.lobby_unavailable()
    end

    test "redirects when riddle is :completed", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("completed")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == GameCopy.lobby_unavailable()
    end

    test "redirects when riddle is :archived", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("archived")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == GameCopy.lobby_unavailable()
    end

    test "mounts successfully when riddle is :ready", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, _live, html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert html =~ GameCopy.lobby_heading()
    end

    test "renders the game topbar with account controls and no bottom nav", %{
      conn: conn,
      user: user
    } do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#topbar-me-chip", user.username)
      assert has_element?(live, "#topbar-log-out")
      refute has_element?(live, ".rg-nav")
    end

    test "redirects to /play when riddle is :live", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")
        |> set_play_status("live")

      conn = log_in_user(conn, user)
      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert path == "/game/#{riddle.id}/play"
    end
  end

  describe "lobby content" do
    setup %{user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      %{riddle: riddle, user: user}
    end

    test "shows the riddle number, category and heading", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, ".rg-lobby__clock .rg-kicker__num", "No. #{riddle.number}")
      assert has_element?(live, ".rg-lobby__clock .rg-kicker", riddle.category.name)
      assert has_element?(live, "h1#lobby-h[tabindex='-1']", GameCopy.lobby_heading())
    end

    test "shows the Lobby status pill in the topbar", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, ".rg-topbar__mid .rg-pill--soon", "Lobby")
      assert has_element?(live, ".rg-topbar__mid .rg-pill__long", "No. #{riddle.number}")
    end

    test "shows the solve time and the scoring rule", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 90})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, ".rg-facts .rg-fact", GameCopy.solve_time("01:30"))
      assert has_element?(live, ".rg-facts .rg-fact", GameCopy.scoring_rule())
      assert has_element?(live, ".rg-fact svg.rg-icon[aria-hidden='true']")
    end

    test "shows countdown element with data-seconds attribute", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert has_element?(live, "#lobby-flaps.rg-flaps[role='timer'][phx-hook][data-seconds]")
    end
  end

  describe "countdown tick" do
    test "shows the seconds until the riddle drops", %{conn: conn, user: user} do
      now = ~U[2026-08-01 12:00:00.000000Z]
      Frozen.freeze(now)

      riddle =
        GamesFixtures.riddle_fixture(%{live_date: DateTime.add(now, 90, :second)})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)

      # Static render: the seconds come from the LiveView's own clock read,
      # before any tick from the lobby timer can land.
      html = conn |> get(~p"/game/#{riddle.id}/lobby") |> html_response(200)

      assert html =~ ~s(data-seconds="90")
      assert html =~ ~s(aria-label="01:30 #{GameCopy.clock_label_tail()}")
    end

    test "handles :tick and updates time_remaining and data-seconds", %{conn: conn, user: user} do
      live_date = DateTime.add(DateTime.utc_now(), 120, :second)

      riddle =
        GamesFixtures.riddle_fixture(%{live_date: live_date})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      refute has_element?(live, "#lobby-flaps[data-seconds='100']")

      send(live.pid, {:countdown_tick, :lobby, 100})

      assert has_element?(live, "#lobby-flaps[data-seconds='100']")
    end

    test "tells players to get ready only in the last five seconds", %{
      conn: conn,
      user: user
    } do
      riddle =
        GamesFixtures.riddle_fixture(%{live_date: DateTime.add(DateTime.utc_now(), 120, :second)})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#lobby-ready[aria-live='assertive']")
      refute has_element?(live, "#lobby-ready", GameCopy.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 6})
      refute has_element?(live, "#lobby-ready", GameCopy.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 5})
      assert has_element?(live, "#lobby-ready", GameCopy.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 1})
      assert has_element?(live, "#lobby-ready", GameCopy.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 0})
      refute has_element?(live, "#lobby-ready", GameCopy.lobby_ready())
    end

    test "sets the topbar countdown dot from the seconds left", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture(%{live_date: DateTime.add(DateTime.utc_now(), 120, :second)})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, ".rg-topbar__mid .rg-pill--soon[data-count='future']")

      send(live.pid, {:countdown_tick, :lobby, 30})
      assert has_element?(live, ".rg-topbar__mid .rg-pill--soon[data-count='warn']")

      send(live.pid, {:countdown_tick, :lobby, 10})
      assert has_element?(live, ".rg-topbar__mid .rg-pill--soon[data-count='urgent']")
    end
  end

  describe "drop time" do
    test "gives the drop time for the browser to show in local time", %{conn: conn, user: user} do
      live_date = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)

      riddle =
        GamesFixtures.riddle_fixture(%{live_date: live_date})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      iso = DateTime.to_iso8601(live_date)
      utc_hhmm = Calendar.strftime(live_date, "%H:%M")

      assert has_element?(live, ".rg-lobby__when", GameCopy.lobby_when_lead())
      assert has_element?(live, ".rg-lobby__when", GameCopy.lobby_when_tail())

      assert has_element?(
               live,
               ".rg-lobby__when time#lobby-drop-time[phx-hook][datetime='#{iso}']",
               utc_hhmm
             )
    end
  end

  describe "PubSub redirect on game start" do
    test "redirects to /play when :riddle_live broadcast received", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      send(live.pid, {:riddle_live, riddle})

      assert_redirect(live, "/game/#{riddle.id}/play")
    end

    test "ignores :riddle_live for a different riddle", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      other_riddle = GamesFixtures.riddle_fixture()

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      send(live.pid, {:riddle_live, other_riddle})

      # Page still showing lobby content
      assert has_element?(live, "#lobby-h", GameCopy.lobby_heading())
    end
  end

  describe "room panel" do
    setup %{user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      %{riddle: riddle, user: user}
    end

    test "puts the viewer's own tile first, labelled you", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#room-h", GameCopy.room_heading())
      assert has_element?(live, "#room-count[aria-live='polite']", GameCopy.room_count(1))

      assert has_element?(
               live,
               "#room-grid li:first-child#room-p-#{user.id}.is-me",
               GameCopy.room_you()
             )

      assert has_element?(
               live,
               "#room-p-#{user.id} .rg-tile",
               GameComponents.initial(user.username)
             )
    end

    test "two players in the same lobby each see both names", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      other = AccountsFixtures.user_fixture()
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(riddle))

      {:ok, other_live, _html} =
        build_conn() |> log_in_user(other) |> live(~p"/game/#{riddle.id}/lobby")

      assert has_element?(
               other_live,
               "#room-grid li:first-child#room-p-#{other.id}",
               GameCopy.room_you()
             )

      assert has_element?(other_live, "#room-p-#{user.id}", user.username)
      assert has_element?(other_live, "#room-count", GameCopy.room_count(2))

      # The first player hears of the second through a presence diff.
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}
      assert has_element?(live, "#room-p-#{other.id}", other.username)

      assert has_element?(
               live,
               "#room-grid li:first-child#room-p-#{user.id}",
               GameCopy.room_you()
             )

      assert has_element?(live, "#room-count", GameCopy.room_count(2))
    end

    test "count and grid follow players joining and leaving", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(riddle))

      pid = track_player(riddle, "p1", "zelda")
      await_diff()
      assert has_element?(live, "#room-p-p1", "zelda")
      assert has_element?(live, "#room-count", GameCopy.room_count(2))

      Process.exit(pid, :kill)
      await_diff()
      refute has_element?(live, "#room-p-p1")
      assert has_element?(live, "#room-count", GameCopy.room_count(1))
    end

    test "fills a small room with empty tiles up to 8", %{conn: conn, riddle: riddle, user: user} do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(riddle))

      assert count_cells(live, ".rg-room__p:not(.rg-room__empty)") == 1
      assert count_cells(live, ".rg-room__empty[aria-hidden='true']") == 7

      track_player(riddle, "p1", "zelda")
      await_diff()
      assert count_cells(live, ".rg-room__empty") == 6
    end

    test "a full room shows a bounded number of tiles and counts the rest", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      for n <- 1..49, do: track_player(riddle, "p#{n}", "player#{n}")

      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      # 4 columns x 3 rows = 12 cells: 10 tiles, then "more" spans two.
      assert has_element?(live, "#room-count", GameCopy.room_count(50))
      assert count_cells(live, ".rg-room__p") == 10
      assert has_element?(live, "#room-grid li:first-child.is-me")
      assert has_element?(live, "#room-grid .rg-room__more", GameCopy.room_more(40))
      refute has_element?(live, "#room-grid .rg-room__empty")
    end

    test "fits the grid to the columns the browser measures", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      for n <- 1..49, do: track_player(riddle, "p#{n}", "player#{n}")

      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      assert has_element?(live, "#room-grid[phx-hook]")

      # 6 columns x 3 rows = 18 cells: 16 tiles and the "more" cell.
      render_hook(live, "room-cols", %{"cols" => 6})
      assert count_cells(live, ".rg-room__p") == 16
      assert has_element?(live, "#room-grid .rg-room__more", GameCopy.room_more(34))

      # Past 12 columns the grid stops growing.
      render_hook(live, "room-cols", %{"cols" => 500})
      assert count_cells(live, ".rg-room__p") == 34
    end

    test "shows how the game works", %{conn: conn, riddle: riddle, user: user} do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#rules-h", GameCopy.rules_heading())

      for rule <- GameCopy.rules() do
        assert has_element?(live, ".rg-rules li", rule)
      end
    end

    test "the ticker names who just joined, never the viewer", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#room-ticker[aria-live='off']")
      refute has_element?(live, "#room-ticker .rg-ticker__text")

      send_diff(live, riddle, %{to_string(user.id) => user.username})
      refute has_element?(live, "#room-ticker .rg-ticker__text")

      send_diff(live, riddle, %{"p1" => "zelda"})
      assert has_element?(live, "#room-ticker .rg-ticker__text b", "zelda")
      assert has_element?(live, "#room-ticker .rg-ticker__text", GameCopy.ticker_tail(0))

      send_diff(live, riddle, %{"p2" => "ann", "p3" => "bo", to_string(user.id) => user.username})
      assert has_element?(live, "#room-ticker .rg-ticker__text b", "ann")
      assert has_element?(live, "#room-ticker .rg-ticker__text", GameCopy.ticker_tail(1))

      # A diff with only leaves keeps the last join on show.
      send_diff(live, riddle, %{}, %{"p1" => "zelda"})
      assert has_element?(live, "#room-ticker .rg-ticker__text b", "ann")
    end
  end

  defp lobby_topic(riddle), do: "game:lobby:#{riddle.id}"

  # Tracks a fake player in a riddle's lobby from its own process, the way a
  # LiveView would. Returns the pid; kill it to make the player leave.
  defp track_player(riddle, id, username) do
    test = self()

    pid =
      spawn(fn ->
        {:ok, _ref} =
          Riddlr.Gameplay.Presence.track(self(), lobby_topic(riddle), to_string(id), %{
            username: username
          })

        send(test, {:tracked, self()})
        Process.sleep(:infinity)
      end)

    assert_receive {:tracked, ^pid}
    pid
  end

  # Waits for the presence diff a join or leave sends. The test must subscribe
  # to the lobby topic first.
  defp await_diff do
    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}
  end

  # Sends the lobby a presence diff by hand, for joins the test cannot make
  # with real tracking (several players at once, or the viewer again).
  defp send_diff(live, riddle, joins, leaves \\ %{}) do
    to_metas = fn players ->
      Map.new(players, fn {id, name} -> {id, %{metas: [%{username: name}]}} end)
    end

    send(live.pid, %Phoenix.Socket.Broadcast{
      topic: lobby_topic(riddle),
      event: "presence_diff",
      payload: %{joins: to_metas.(joins), leaves: to_metas.(leaves)}
    })
  end

  defp count_cells(live, selector) do
    live
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#room-grid " <> selector)
    |> Enum.count()
  end

  # Helper to directly set play_status bypassing changeset transition validation
  defp set_play_status(riddle, new_status) do
    riddle
    |> Ecto.Changeset.change(play_status: new_status)
    |> Riddlr.Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end
end
