defmodule RiddlrWeb.GameLive.PlayTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.{Games, AccountsFixtures, GamesFixtures}

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user}
  end

  describe "mount access control" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/game/#{riddle.id}/play")
    end

    test "redirects to lobby when riddle is :closed", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/game/#{riddle.id}/play")
      assert path == "/game/#{riddle.id}/lobby"
    end

    test "redirects to lobby when riddle is :scheduled", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("scheduled")
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/game/#{riddle.id}/play")
      assert path == "/game/#{riddle.id}/lobby"
    end

    test "redirects to lobby when riddle is :ready", %{conn: conn, user: user} do
      riddle =
        GamesFixtures.riddle_fixture()
        |> set_play_status("scheduled")
        |> set_play_status("ready")

      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/game/#{riddle.id}/play")
      assert path == "/game/#{riddle.id}/lobby"
    end

    test "redirects home when riddle is :archived", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("archived")
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/game/#{riddle.id}/play")

      assert flash["info"] == "That game has ended."
    end

    test "mounts successfully when riddle is :live", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#riddle-name", riddle.name)
    end

    test "mounts successfully when riddle is :completed (view-only)", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#riddle-name", riddle.name)
      assert has_element?(live, "#game-over")
      refute has_element?(live, "#answer-form-container")
    end
  end

  describe "game content" do
    setup %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      %{riddle: riddle, user: user}
    end

    test "displays riddle name", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#riddle-name", riddle.name)
    end

    test "displays riddle description", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#riddle-description", riddle.description)
    end

    test "displays category and difficulty", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "span", riddle.category.name)
      assert has_element?(live, "span", riddle.difficulty)
    end

    test "shows answer form", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#answer-form")
      assert has_element?(live, "#answer-input")
    end
  end

  describe "answer submission" do
    setup %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      %{riddle: riddle, user: user}
    end

    test "correct answer shows success result", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # riddle_fixture sets answers: ["keyboard", "a keyboard"]
      html =
        live
        |> form("#answer-form", %{answer: "keyboard"})
        |> render_submit()

      assert html =~ "Correct!"
      assert has_element?(live, "#correct-result")
    end

    test "incorrect answer shows incorrect feedback", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      _html =
        live
        |> form("#answer-form", %{answer: "wrong answer"})
        |> render_submit()

      assert has_element?(live, "#incorrect-feedback")
    end

    test "case-insensitive matching — KEYBOARD matches keyboard", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      html =
        live
        |> form("#answer-form", %{answer: "KEYBOARD"})
        |> render_submit()

      assert html =~ "Correct!"
    end

    test "trims whitespace — '  keyboard  ' matches", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      html =
        live
        |> form("#answer-form", %{answer: "  keyboard  "})
        |> render_submit()

      assert html =~ "Correct!"
    end

    test "hides form after correct answer", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      refute has_element?(live, "#answer-form-container")
    end

    test "shows placement and points for correct answer", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      html =
        live
        |> form("#answer-form", %{answer: "keyboard"})
        |> render_submit()

      # 1st place = 10 points
      assert html =~ "1st"
      assert html =~ "+10 points"
    end

    test "empty answer shows error feedback", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      html =
        live
        |> form("#answer-form", %{answer: "   "})
        |> render_submit()

      assert html =~ "Answer cannot be empty"
    end

    test "too-long answer shows error feedback", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      html =
        live
        |> form("#answer-form", %{answer: String.duplicate("a", 501)})
        |> render_submit()

      assert html =~ "too long"
    end

    test "form hidden and riddle assign updated when game transitions to completed", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # Simulate game ending via PubSub — riddle assign must also be updated (W2 fix)
      completed_riddle = %{riddle | play_status: "completed"}
      send(live.pid, {:riddle_completed, completed_riddle})

      refute has_element?(live, "#answer-form-container")
      assert has_element?(live, "#game-over")
    end

    test "cooldown blocks rapid submissions", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # First submission triggers cooldown
      live
      |> form("#answer-form", %{answer: "wrong"})
      |> render_submit()

      # Second immediate submission should be blocked
      html =
        live
        |> form("#answer-form", %{answer: "keyboard"})
        |> render_submit()

      assert html =~ "wait a moment"
    end

    test "duplicate submission blocked after correct answer", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      # Form is hidden, so no second submission possible — verify already_solved state
      refute has_element?(live, "#answer-form-container")
      assert has_element?(live, "#correct-result")
    end
  end

  describe "multi-user placement" do
    test "2nd solver gets 7 points", %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      user2 = AccountsFixtures.user_fixture()

      # user1 solves first (direct ETS insert with past timestamp)
      past_ts = System.monotonic_time(:microsecond) - 1000
      :ets.insert(:riddle_answers, {{riddle.id, user.id}, "keyboard", past_ts, true})

      conn2 = log_in_user(build_conn(), user2)
      {:ok, live2, _html} = live(conn2, ~p"/game/#{riddle.id}/play")

      html =
        live2
        |> form("#answer-form", %{answer: "keyboard"})
        |> render_submit()

      assert html =~ "2nd"
      assert html =~ "+7 points"
    end

    test "3rd solver gets 3 points", %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      user2 = AccountsFixtures.user_fixture()
      user3 = AccountsFixtures.user_fixture()

      past1 = System.monotonic_time(:microsecond) - 2000
      past2 = System.monotonic_time(:microsecond) - 1000
      :ets.insert(:riddle_answers, {{riddle.id, user.id}, "keyboard", past1, true})
      :ets.insert(:riddle_answers, {{riddle.id, user2.id}, "keyboard", past2, true})

      conn3 = log_in_user(build_conn(), user3)
      {:ok, live3, _html} = live(conn3, ~p"/game/#{riddle.id}/play")

      html =
        live3
        |> form("#answer-form", %{answer: "keyboard"})
        |> render_submit()

      assert html =~ "3rd"
      assert html =~ "+3 points"
    end
  end

  describe "game state transitions via PubSub" do
    test "shows game-over UI when :riddle_completed received", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:riddle_completed, riddle})

      assert has_element?(live, "#game-over")
      refute has_element?(live, "#answer-form-container")
    end

    test "ignores :riddle_completed for a different riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      other = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:riddle_completed, other})

      assert has_element?(live, "#answer-form-container")
    end

    test "redirects home when :riddle_archived received", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:riddle_archived, riddle})

      assert_redirect(live, "/")
    end
  end

  describe "ban enforcement" do
    test "banned user is redirected when submitting", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # Ban the user directly in DB
      import Ecto.Query

      user_id = user.id

      Riddlr.Repo.update_all(
        from(u in Riddlr.Accounts.User, where: u.id == ^user_id),
        set: [account_status: "banned"]
      )

      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      assert_redirect(live, "/")
    end
  end

  # Helper to directly set play_status bypassing changeset transition validation
  defp set_play_status(riddle, new_status) do
    riddle
    |> Ecto.Changeset.change(play_status: new_status)
    |> Riddlr.Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end

  # Alias for multi-step transitions
  defp set_play_status_direct(riddle, status), do: set_play_status(riddle, status)
end
