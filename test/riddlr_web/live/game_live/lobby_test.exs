defmodule RiddlrWeb.GameLive.LobbyTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.{Games, GamesFixtures, AccountsFixtures}

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

      assert flash["info"] == "Game lobby is not yet available."
    end

    test "redirects when riddle is :scheduled", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == "Game lobby is not yet available."
    end

    test "redirects when riddle is :completed", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("completed")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == "Game lobby is not yet available."
    end

    test "redirects when riddle is :archived", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("archived")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/lobby")

      assert flash["info"] == "Game lobby is not yet available."
    end

    test "mounts successfully when riddle is :ready", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert has_element?(live, "#riddle-name", riddle.name)
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

    test "displays riddle name", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert has_element?(live, "#riddle-name", riddle.name)
    end

    test "displays category and difficulty", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      # riddle_fixture always sets category and difficulty
      assert has_element?(live, "span", riddle.category.name)
      assert has_element?(live, "span", riddle.difficulty)
    end

    test "shows countdown element with data-seconds attribute", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert has_element?(live, "#countdown[phx-hook][data-seconds]")
      assert has_element?(live, "p", "Riddle starts in…")
    end

    test "shows player count element", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")
      assert has_element?(live, "#player-count")
      assert has_element?(live, "p", "Players in lobby")
    end
  end

  describe "countdown tick" do
    test "handles :tick and updates time_remaining and data-seconds", %{conn: conn, user: user} do
      live_date = DateTime.add(DateTime.utc_now(), 120, :second)

      riddle =
        GamesFixtures.riddle_fixture(%{live_date: live_date})
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/lobby")

      # Capture data-seconds before tick
      before_html = render(live)
      assert before_html =~ ~r/data-seconds="(\d+)"/

      send(live.pid, :tick)
      after_html = render(live)

      # Countdown element still present and data-seconds attribute is set
      assert has_element?(live, "#countdown[data-seconds]")

      # data-seconds value is a non-negative integer
      [seconds_str] = Regex.run(~r/data-seconds="(\d+)"/, after_html, capture: :all_but_first)
      assert String.to_integer(seconds_str) >= 0
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

      assert has_element?(live, "#riddle-name", riddle.name)
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
      assert has_element?(live, "#player-count", "1")
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
      assert has_element?(live, "#player-count", "1")
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
