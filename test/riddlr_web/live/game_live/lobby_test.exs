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
    test "lets a guest watch the lobby", %{conn: conn} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "h1#lobby-h")
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

      assert flash["info"] == GameCopy.Lobby.lobby_unavailable()
    end

    test "redirects when riddle is :scheduled", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == GameCopy.Lobby.lobby_unavailable()
    end

    test "redirects when riddle is :completed", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("completed")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == GameCopy.Lobby.lobby_unavailable()
    end

    test "redirects when riddle is :archived", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("archived")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == GameCopy.Lobby.lobby_unavailable()
    end

    test "mounts successfully when riddle is :ready", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, _live, html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert html =~ GameCopy.Lobby.lobby_heading()
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

      assert has_element?(live, ".rg-lobby__clock .rg-kicker__num", "#{riddle.number}")

      assert has_element?(
               live,
               ".rg-lobby__clock .rg-kicker",
               "#{riddle.name} · #{riddle.category.name}"
             )

      assert has_element?(live, "h1#lobby-h[tabindex='-1']", GameCopy.Lobby.lobby_heading())
    end

    test "shows the Lobby status pill in the topbar", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, ".rg-topbar__mid .rg-pill--soon")
      assert has_element?(live, ".rg-topbar__mid .rg-pill__long", "#{riddle.number}")
    end

    test "shows the solve time as its only fact", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 90})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, ".rg-facts .rg-fact", GameCopy.Lobby.solve_time("01:30"))
      refute has_element?(live, ".rg-facts .rg-fact:nth-child(2)")
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
      refute has_element?(live, "#lobby-ready", GameCopy.Lobby.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 6})
      refute has_element?(live, "#lobby-ready", GameCopy.Lobby.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 5})
      assert has_element?(live, "#lobby-ready", GameCopy.Lobby.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 1})
      assert has_element?(live, "#lobby-ready", GameCopy.Lobby.lobby_ready())

      send(live.pid, {:countdown_tick, :lobby, 0})
      refute has_element?(live, "#lobby-ready", GameCopy.Lobby.lobby_ready())
    end

    test "does not tell a guest to get ready", %{conn: conn} do
      riddle =
        GamesFixtures.riddle_fixture(%{live_date: DateTime.add(DateTime.utc_now(), 120, :second)})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      send(live.pid, {:countdown_tick, :lobby, 5})

      refute has_element?(live, "#lobby-ready")
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
    test "shows the drop time in Eastern time, with a local-time line", %{conn: conn, user: user} do
      live_date = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)

      riddle =
        GamesFixtures.riddle_fixture(%{live_date: live_date})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      iso = DateTime.to_iso8601(live_date)

      assert has_element?(live, ".rg-lobby__when", GameCopy.Lobby.lobby_when_lead())
      assert has_element?(live, ".rg-lobby__when", GameCopy.Lobby.lobby_when_tail())

      assert has_element?(
               live,
               ".rg-lobby__when time#lobby-drop-time[datetime='#{iso}']",
               RiddlrWeb.DropTime.short(live_date, DateTime.utc_now(), mid_sentence: true)
             )

      assert has_element?(live, "#lobby-drop-local.rg-drop-local[hidden][data-at='#{iso}']")
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

    test "waits a random moment before leaving, so players spread out", %{
      conn: conn,
      user: user
    } do
      put_stagger(60_000)

      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      send(live.pid, {:riddle_live, riddle})
      assert has_element?(live, "#lobby-h")

      send(live.pid, {:stagger_navigate, "/game/#{riddle.id}/play"})
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
      assert has_element?(live, "#lobby-h", GameCopy.Lobby.lobby_heading())
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

      assert has_element?(live, "#room-h", GameCopy.Lobby.room_heading())
      assert has_element?(live, "#room-count[aria-live='polite']", GameCopy.Lobby.room_count(1))

      assert has_element?(
               live,
               "#room-grid li:first-child#room-p-#{user.id}.is-me",
               GameCopy.Lobby.room_you()
             )

      assert has_element?(
               live,
               "#room-p-#{user.id} .rg-tile",
               GameComponents.initial(user.username)
             )
    end

    test "a guest sees the players in the room but is not one of them", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      {:ok, _player_live, _html} =
        build_conn() |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#room-p-#{user.id}:not(.is-me)", user.username)
      refute has_element?(live, "#room-grid .is-me")
      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(1))
    end

    test "invites a guest to log in or sign up", %{conn: conn, riddle: riddle} do
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#join-note a[href='/users/log-in']")
      assert has_element?(live, "#join-note a[href='/users/register']")
    end

    test "does not invite a signed-in player to join", %{conn: conn, riddle: riddle, user: user} do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      refute has_element?(live, "#join-note")
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
               GameCopy.Lobby.room_you()
             )

      assert has_element?(other_live, "#room-p-#{user.id}", user.username)
      assert has_element?(other_live, "#room-count", GameCopy.Lobby.room_count(2))

      # The first player hears of the second through a presence diff.
      await_diff(:joins, to_string(other.id))
      flush_room(live)
      assert has_element?(live, "#room-p-#{other.id}", other.username)

      assert has_element?(
               live,
               "#room-grid li:first-child#room-p-#{user.id}",
               GameCopy.Lobby.room_you()
             )

      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(2))
    end

    test "count and grid follow players joining and leaving", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(riddle))

      pid = track_player(riddle, "p1", "zelda")
      await_diff(:joins, "p1")
      flush_room(live)
      assert has_element?(live, "#room-p-p1", "zelda")
      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(2))

      Process.exit(pid, :kill)
      await_diff(:leaves, "p1")
      flush_room(live)
      refute has_element?(live, "#room-p-p1")
      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(1))
    end

    test "fills a small room with empty tiles up to 8", %{conn: conn, riddle: riddle, user: user} do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(riddle))

      assert count_cells(live, ".rg-room__p:not(.rg-room__empty)") == 1
      assert count_cells(live, ".rg-room__empty[aria-hidden='true']") == 7

      track_player(riddle, "p1", "zelda")
      await_diff(:joins, "p1")
      flush_room(live)
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
      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(50))
      assert count_cells(live, ".rg-room__p") == 10
      assert has_element?(live, "#room-grid li:first-child.is-me")
      assert has_element?(live, "#room-grid .rg-room__more", GameCopy.Lobby.room_more(40))
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
      assert has_element?(live, "#room-grid .rg-room__more", GameCopy.Lobby.room_more(34))

      # Past 12 columns the grid stops growing.
      render_hook(live, "room-cols", %{"cols" => 500})
      assert count_cells(live, ".rg-room__p") == 34
    end

    test "shows how the game works", %{conn: conn, riddle: riddle, user: user} do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")

      assert has_element?(live, "#rules-h", GameCopy.Lobby.rules_heading())

      for rule <- GameCopy.Lobby.rules() do
        assert has_element?(live, ".rg-rules li", rule)
      end
    end

    test "holds diffs until the flush, then applies them in one update", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      before = render(live)

      for n <- 1..100, do: push_diff(live, riddle, %{"p#{n}" => "player#{n}"})
      for n <- 1..50, do: push_diff(live, riddle, %{}, %{"p#{n}" => "player#{n}"})

      assert render(live) == before

      flush_room(live)

      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(51))
      refute has_element?(live, "#room-p-p1")
      assert has_element?(live, "#room-ticker .rg-ticker__text", GameCopy.Lobby.ticker_tail(49))
    end

    test "a diff the mount already read changes nothing", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(riddle))
      pid = track_player(riddle, "p1", "zelda")
      %Phoenix.Socket.Broadcast{payload: join} = await_diff(:joins, "p1")

      {:ok, live, _html} = conn |> log_in_user(user) |> live(~p"/game/#{riddle.id}/lobby")
      send(live.pid, %Phoenix.Socket.Broadcast{event: "presence_diff", payload: join})
      flush_room(live)
      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(2))

      Process.exit(pid, :kill)
      await_diff(:leaves, "p1")
      flush_room(live)
      assert has_element?(live, "#room-count", GameCopy.Lobby.room_count(1))
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
      assert has_element?(live, "#room-ticker .rg-ticker__text", GameCopy.Lobby.ticker_tail(0))

      send_diff(live, riddle, %{"p2" => "ann", "p3" => "bo", to_string(user.id) => user.username})
      assert has_element?(live, "#room-ticker .rg-ticker__text b", "ann")
      assert has_element?(live, "#room-ticker .rg-ticker__text", GameCopy.Lobby.ticker_tail(1))

      # A diff with only leaves keeps the last join on show.
      send_diff(live, riddle, %{}, %{"p1" => "zelda"})
      assert has_element?(live, "#room-ticker .rg-ticker__text b", "ann")
    end
  end

  defp put_stagger(max_ms) do
    config = Application.get_env(:riddlr, RiddlrWeb.GameLive.Stagger)
    Application.put_env(:riddlr, RiddlrWeb.GameLive.Stagger, max_ms: max_ms)
    on_exit(fn -> Application.put_env(:riddlr, RiddlrWeb.GameLive.Stagger, config) end)
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

  # Waits for the presence diff in which player `id` joins or leaves. The
  # test must subscribe to the lobby topic first. Other diffs, like the
  # viewer's own join, can arrive in between, so it matches on the player.
  #
  # A tracker shard sends a diff to one subscriber after another, so the test
  # can hear of it before the lobby does. Waiting on the shards makes sure the
  # lobby has it too.
  defp await_diff(kind, id) do
    assert_receive %Phoenix.Socket.Broadcast{
                     event: "presence_diff",
                     payload: %{^kind => %{^id => _}}
                   } = diff

    for name <- Process.registered(),
        String.starts_with?(Atom.to_string(name), "Elixir.Riddlr.Gameplay.Presence_shard"),
        do: :sys.get_state(name)

    diff
  end

  # Sends the lobby a presence diff by hand, for joins the test cannot make
  # with real tracking (several players at once, or the viewer again), then
  # applies it.
  defp send_diff(live, riddle, joins, leaves \\ %{}) do
    push_diff(live, riddle, joins, leaves)
    flush_room(live)
  end

  # Sends a presence diff by hand without applying it. One presence per
  # player, with a phx_ref made from the player id.
  defp push_diff(live, riddle, joins, leaves \\ %{}) do
    to_metas = fn players ->
      Map.new(players, fn {id, name} ->
        {id, %{metas: [%{username: name, phx_ref: "ref-#{id}"}]}}
      end)
    end

    send(live.pid, %Phoenix.Socket.Broadcast{
      topic: lobby_topic(riddle),
      event: "presence_diff",
      payload: %{joins: to_metas.(joins), leaves: to_metas.(leaves)}
    })
  end

  # Applies the diffs the lobby holds, as its flush timer would.
  defp flush_room(live), do: send(live.pid, :flush_room)

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
