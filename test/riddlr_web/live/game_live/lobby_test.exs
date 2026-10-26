defmodule RiddlrWeb.GameLive.LobbyTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.Clock.Frozen
  alias Riddlr.{Games, GamesFixtures, AccountsFixtures}
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

    test "shows player count element", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert has_element?(live, "#lobby-player-count", GameCopy.players_waiting(1))
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

  describe "Presence player count" do
    test "renders player count of 1 after own connection", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      # Connected LiveView test triggers Presence.track, so count is 1
      assert has_element?(live, "#lobby-player-count", GameCopy.players_waiting(1))
    end

    test "updates player count when Presence diff received", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      send(
        live.pid,
        %Phoenix.Socket.Broadcast{
          topic: "game:lobby:#{riddle.id}",
          event: "presence_diff",
          payload: %{joins: %{}, leaves: %{}}
        }
      )

      # Player count re-renders after diff; connected mount tracks 1 player
      assert has_element?(live, "#lobby-player-count", GameCopy.players_waiting(1))
    end
  end

  # Helper to directly set play_status bypassing changeset transition validation
  defp set_play_status(riddle, new_status) do
    riddle
    |> Ecto.Changeset.change(play_status: new_status)
    |> Riddlr.Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end
end
