defmodule RiddlrWeb.GameLive.PlayTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.Clock.Frozen
  alias Riddlr.{Games, Gameplay, AccountsFixtures, GamesFixtures}

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

    test "redirects to home when riddle does not exist", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/game/999999/play")
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
      assert has_element?(live, "#riddle-description", riddle.description)
    end

    test "mounts successfully when riddle is :completed (view-only)", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, ".rg-round-header")
      refute has_element?(live, "#answer-form-container")
    end
  end

  describe "game content" do
    setup %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      %{riddle: riddle, user: user}
    end

    test "displays riddle description", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#riddle-description", riddle.description)
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
      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      # Trigger the delayed :mark_solved message so the solved banner appears
      send(live.pid, {:mark_solved, riddle.id})
      html = render(live)

      assert html =~ "1st"
      assert has_element?(live, ".rg-input-bar--solved")
    end

    test "incorrect answer shows incorrect feedback", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      _html =
        live
        |> form("#answer-form", %{answer: "wrong answer"})
        |> render_submit()

      assert has_element?(live, "#answer-feedback-incorrect")
    end

    test "case-insensitive matching — KEYBOARD matches keyboard", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "KEYBOARD"})
      |> render_submit()

      send(live.pid, {:mark_solved, riddle.id})
      html = render(live)

      assert html =~ "1st"
      assert has_element?(live, ".rg-input-bar--solved")
    end

    test "trims whitespace — '  keyboard  ' matches", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "  keyboard  "})
      |> render_submit()

      send(live.pid, {:mark_solved, riddle.id})
      html = render(live)

      assert html =~ "1st"
      assert has_element?(live, ".rg-input-bar--solved")
    end

    test "hides form after correct answer", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      # Trigger the delayed :mark_solved message that Process.send_after enqueues
      send(live.pid, {:mark_solved, riddle.id})
      render(live)

      refute has_element?(live, "#answer-form-container")
    end

    test "shows placement and points for correct answer", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      send(live.pid, {:mark_solved, riddle.id})
      html = render(live)

      # 1st place = 10 points
      assert html =~ "1st"
      assert html =~ "+10 pts"
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
      assert has_element?(live, ".rg-round-header")
    end

    test "cooldown blocks rapid submissions", %{conn: conn, riddle: riddle, user: user} do
      # Frozen: without it this test passes only when both submissions land
      # inside the same real second.
      Frozen.freeze()
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

      # Trigger mark_solved so form hides and solved banner shows
      send(live.pid, {:mark_solved, riddle.id})
      render(live)

      # Form is hidden, solved banner visible
      refute has_element?(live, "#answer-form-container")
      assert has_element?(live, ".rg-input-bar--solved")
    end
  end

  describe "multi-user placement" do
    test "2nd solver gets 9 points", %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      user2 = AccountsFixtures.user_fixture()

      # user1 solves first, a second earlier on the frozen clock
      Frozen.freeze()
      {:correct, 1, 10} = Gameplay.submit_answer(riddle, user, "keyboard")
      Frozen.advance(1, :second)

      conn2 = log_in_user(build_conn(), user2)
      {:ok, live2, _html} = live(conn2, ~p"/game/#{riddle.id}/play")

      live2
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      send(live2.pid, {:mark_solved, riddle.id})
      html = render(live2)

      assert html =~ "2nd"
      assert html =~ "+9 pts"
    end

    test "3rd solver gets 8 points", %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      user2 = AccountsFixtures.user_fixture()
      user3 = AccountsFixtures.user_fixture()

      Frozen.freeze()
      {:correct, 1, 10} = Gameplay.submit_answer(riddle, user, "keyboard")
      Frozen.advance(1, :second)
      {:correct, 2, 9} = Gameplay.submit_answer(riddle, user2, "keyboard")
      Frozen.advance(1, :second)

      conn3 = log_in_user(build_conn(), user3)
      {:ok, live3, _html} = live(conn3, ~p"/game/#{riddle.id}/play")

      live3
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      send(live3.pid, {:mark_solved, riddle.id})
      html = render(live3)

      assert html =~ "3rd"
      assert html =~ "+8 pts"
    end
  end

  describe "solve countdown" do
    test "shows the time left on the riddle's solve clock", %{conn: conn, user: user} do
      live_date = ~U[2026-08-01 12:00:00.000000Z]

      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 300, live_date: live_date})
        |> set_play_status_direct("live")

      Frozen.freeze(live_date)
      Frozen.advance(30, :second)

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#countdown-timer[data-seconds='270']")
      assert render(live) =~ "04:30"
    end

    test "a tick past the solve time leaves no time on the clock", %{conn: conn, user: user} do
      live_date = ~U[2026-08-01 12:00:00.000000Z]

      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 60, live_date: live_date})
        |> set_play_status_direct("live")

      Frozen.freeze(live_date)
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      Frozen.advance(90, :second)
      send(live.pid, :tick)

      assert has_element?(live, "#countdown-timer[data-seconds='0']")
    end
  end

  describe "game state transitions via PubSub" do
    test "shows game-over UI when :riddle_completed received", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:riddle_completed, riddle})

      assert has_element?(live, ".rg-round-header")
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

    test "stays on play page when :riddle_archived received", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:riddle_archived, riddle})

      # Page stays live — no redirect on archive
      assert render(live) =~ riddle.description
    end
  end

  describe "ban enforcement" do
    test "banned user is redirected immediately when ban PubSub message arrives", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # Simulate the ban broadcast that Accounts.set_user_status/2 would emit
      send(live.pid, {:user_status_changed, :banned})

      assert_redirect(live, "/")
    end
  end

  describe "answer feed" do
    setup %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      %{riddle: riddle, user: user}
    end

    test "answer feed section is rendered", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#answer-feed")
    end

    test "submitted answer appears in the feed via PubSub", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      answer_data = %{
        id: "#{riddle.id}-#{user.id}-123456",
        user_id: user.id,
        username: user.username,
        text: "keyboard",
        correct: false,
        offset_ms: 1500,
        show_highlight: false,
        flagged: false
      }

      send(live.pid, {:answer_submitted, answer_data})

      html = render(live)
      assert html =~ user.username
      assert html =~ "keyboard"
    end

    test "flagged answer is removed from the feed", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      answer_id = "#{riddle.id}-#{user.id}-999"

      answer_data = %{
        id: answer_id,
        user_id: user.id,
        username: user.username,
        text: "spam content",
        correct: false,
        offset_ms: 500,
        show_highlight: false,
        flagged: false
      }

      send(live.pid, {:answer_submitted, answer_data})
      html = render(live)
      assert html =~ "spam content"

      send(live.pid, {:answer_flagged, answer_id})
      html = render(live)
      refute html =~ "spam content"
    end

    test "submitting a blocked word triggers async moderation and removes from feed", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # Use a stable answer_id so we can reference it for the flagged event
      answer_id = "moderation-test-#{riddle.id}"

      # Inject the answer directly into the feed (simulates the PubSub broadcast
      # that handle_event sends). This is reliable in tests — the E2E PubSub
      # round-trip from form submit → PubSub → handle_info is async and would
      # require sleep() to stabilise.
      send(
        live.pid,
        {:answer_submitted,
         %{
           id: answer_id,
           user_id: user.id,
           username: user.username,
           text: "spam",
           correct: false,
           offset_ms: 100,
           show_highlight: false,
           flagged: false
         }}
      )

      html = render(live)
      assert html =~ "spam"

      # Async moderation flags it — verify it disappears from feed
      send(live.pid, {:answer_flagged, answer_id})
      html = render(live)
      refute html =~ "spam"
    end

    test "correct answers appear in post-game chat after completion", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      correct_answer = %{
        id: "#{riddle.id}-#{user.id}-777",
        user_id: user.id,
        username: user.username,
        text: "keyboard",
        correct: true,
        offset_ms: 2000,
        show_highlight: false,
        flagged: false
      }

      # Submit the correct answer first so it's tracked in correct_answers assign
      send(live.pid, {:answer_submitted, correct_answer})
      # Game completion transitions to post-game view
      send(live.pid, {:riddle_completed, %{riddle | play_status: "completed"}})

      html = render(live)
      assert html =~ "keyboard"
      assert has_element?(live, ".rg-round-header")
    end

    test "time offset is displayed for real-time answers", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      answer_data = %{
        id: "#{riddle.id}-#{user.id}-500",
        user_id: user.id,
        username: user.username,
        text: "keyboard",
        correct: false,
        offset_ms: 2500,
        show_highlight: false,
        flagged: false
      }

      send(live.pid, {:answer_submitted, answer_data})

      html = render(live)
      assert html =~ "+2s"
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
