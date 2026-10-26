defmodule RiddlrWeb.GameLive.PlayTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.Clock.Frozen
  alias Riddlr.GameClock
  alias Riddlr.Gameplay.Answer
  alias Riddlr.{Games, Gameplay, AccountsFixtures, GamesFixtures}
  alias RiddlrWeb.GameCopy

  @mask Riddlr.Moderation.mask()
  @bad_word Riddlr.ModerationFixtures.bad_word()

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
      assert has_element?(live, "#play-h[aria-label='#{riddle.description}']")
    end

    test "redirects to results when riddle is :completed", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("completed")
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/game/#{riddle.id}/play")
      assert path == "/game/#{riddle.id}/results"
    end
  end

  describe "game content" do
    setup %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      %{riddle: riddle, user: user}
    end

    test "renders the game topbar with account controls and no bottom nav", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#topbar-me-chip", user.username)
      assert has_element?(live, "#topbar-log-out")
      refute has_element?(live, ".rg-nav")
    end

    test "displays riddle description", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "#play-h[aria-label='#{riddle.description}']")
    end

    test "locks the page so only the feed scrolls", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, "main.rg-main.is-locked .rg-play")
    end

    test "shows the riddle word by word, hidden from screen readers", %{
      conn: conn,
      user: user
    } do
      riddle =
        GamesFixtures.riddle_fixture(%{description: "What has keys  but no locks?"})
        |> set_play_status_direct("live")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#play-h .rg-riddle__w[aria-hidden='true']", "What")
      assert has_element?(live, "#play-h .rg-riddle__w:nth-child(6)", "locks?")
      refute has_element?(live, "#play-h .rg-riddle__w:nth-child(7)")
    end

    test "hooks focus, guess feedback and feed scrolling", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#play-root[phx-hook$='.PlayFocus']")
      assert has_element?(live, "#answer-form[phx-hook$='.GuessForm']")
      assert has_element?(live, "#answer-feed[phx-hook$='.FeedScroll']")
    end

    test "shows the riddle's kicker", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      assert has_element?(live, ".rg-play__riddle .rg-kicker", riddle.category.name)
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

      html = render(live)

      assert html =~ "1st"
      assert has_element?(live, "#solved-panel")
    end

    test "incorrect answer shows incorrect feedback", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      _html =
        live
        |> form("#answer-form", %{answer: "wrong answer"})
        |> render_submit()

      assert has_element?(live, "#answer-input[aria-invalid='true']")
      assert has_element?(live, "#guess-msg.is-wrong[role='status']")
      assert Enum.any?(GameCopy.quips(), &has_element?(live, "#guess-msg", &1))
    end

    test "a second wrong guess never repeats the same line", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      Frozen.freeze()
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      first = live |> form("#answer-form", %{answer: "piano"}) |> render_submit()
      Frozen.advance(1, :second)
      second = live |> form("#answer-form", %{answer: "organ"}) |> render_submit()

      line = fn html ->
        html |> LazyHTML.from_fragment() |> LazyHTML.query("#guess-msg") |> LazyHTML.text()
      end

      refute line.(first) == line.(second)
    end

    test "renders the guess form", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "label[for='answer-input']", "Your answer")
      assert has_element?(live, "#answer-input[aria-describedby='guess-msg']")
      assert has_element?(live, "#guess-btn:not([disabled])", "Guess")
    end

    test "the button reads Wait for a second after each guess", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live |> form("#answer-form", %{answer: "piano"}) |> render_submit()
      assert has_element?(live, "#guess-btn[disabled]", "Wait")

      send(live.pid, :cooldown_over)
      assert has_element?(live, "#guess-btn:not([disabled])", "Guess")
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

      html = render(live)

      assert html =~ "1st"
      assert has_element?(live, "#solved-panel")
    end

    test "trims whitespace — '  keyboard  ' matches", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "  keyboard  "})
      |> render_submit()

      html = render(live)

      assert html =~ "1st"
      assert has_element?(live, "#solved-panel")
    end

    test "hides form after correct answer", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      render(live)

      refute has_element?(live, "#answer-form")
    end

    test "solving swaps the form for the solved panel at once", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live |> form("#answer-form", %{answer: "keyboard"}) |> render_submit()

      refute has_element?(live, "#answer-form")
      assert has_element?(live, "#solved-panel #solved-stamp:not(.is-none)", "1ST")
      assert has_element?(live, "#solved-panel .rg-solved__title", "First! Nobody was faster.")

      assert has_element?(
               live,
               "#solved-panel .rg-solved__sub",
               "+10 pts · round closes in #{GameCopy.m_ss(riddle.solve_time)}. Watch the others sweat."
             )
    end

    test "the solved panel counts down with the round", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live |> form("#answer-form", %{answer: "keyboard"}) |> render_submit()

      Phoenix.PubSub.broadcast(
        Riddlr.PubSub,
        GameClock.topic(riddle.id),
        {:countdown_tick, :play, 75}
      )

      assert has_element?(live, "#solved-panel .rg-solved__sub", "round closes in 1:15")
    end

    test "a player who solved and reloads sees their result again", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      first = AccountsFixtures.user_fixture()
      Frozen.freeze()
      {:correct, 1, 10} = Gameplay.submit_answer(riddle, first, "keyboard")
      Frozen.advance(1, :second)
      {:correct, 2, 9} = Gameplay.submit_answer(riddle, user, "keyboard")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      refute has_element?(live, "#answer-form")
      assert has_element?(live, "#solved-stamp", "2ND")
      assert has_element?(live, ".rg-solved__title", "Cracked it. 2nd place.")
      assert has_element?(live, ".rg-solved__sub", "+9 pts")
    end

    test "a solve outside the top 10 gets a grey stamp", %{conn: conn, riddle: riddle, user: user} do
      Frozen.freeze()

      for _ <- 1..10 do
        {:correct, _, _} =
          Gameplay.submit_answer(riddle, AccountsFixtures.user_fixture(), "keyboard")

        Frozen.advance(1, :second)
      end

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")
      live |> form("#answer-form", %{answer: "keyboard"}) |> render_submit()

      assert has_element?(live, "#solved-stamp.is-none", "11TH")
      assert has_element?(live, ".rg-solved__title", "Cracked it — just off the board.")
      assert has_element?(live, ".rg-solved__sub", "+0 pts")
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

      html = render(live)

      # 1st place = 10 points
      assert html =~ "1st"
      assert html =~ "+10 pts"
    end

    test "empty answer shows error feedback", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "   "})
      |> render_submit()

      assert has_element?(live, "#guess-msg.is-wrong", "Type an answer first.")
      assert has_element?(live, "#guess-btn:not([disabled])", "Guess")
    end

    test "too-long answer shows error feedback", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: String.duplicate("a", 501)})
      |> render_submit()

      assert has_element?(live, "#guess-msg", "too long")
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

      # Second immediate submission should be blocked. The button is disabled
      # by then, so this stands in for a guess that slips through.
      render_submit(live, "submit_answer", %{answer: "keyboard"})

      assert has_element?(live, "#guess-msg", "One guess per second. Breathe.")
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

      render(live)

      # Form is hidden, solved panel visible
      refute has_element?(live, "#answer-form")
      assert has_element?(live, "#solved-panel")
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

      assert has_element?(live, "#countdown-timer[data-seconds='270']", "4:30")
      assert has_element?(live, "time#countdown-timer[role='timer'][aria-label='Time left']")
      assert has_element?(live, ".rg-clockbar .rg-live-dot")
      assert has_element?(live, ".rg-clockbar", "Live")
      assert has_element?(live, "#play-solved")
    end

    test "the track fill shows the share of time left", %{conn: conn, user: user} do
      live_date = ~U[2026-08-01 12:00:00.000000Z]

      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 200, live_date: live_date})
        |> set_play_status_direct("live")

      Frozen.freeze(live_date)
      Frozen.advance(50, :second)

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#play-fill[style*='scaleX(0.75)']")
    end

    test "warns at 20s and turns critical at 10s", %{conn: conn, user: user} do
      live_date = ~U[2026-08-01 12:00:00.000000Z]

      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 60, live_date: live_date})
        |> set_play_status_direct("live")

      Frozen.freeze(live_date)
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      tick = fn seconds ->
        Phoenix.PubSub.broadcast(
          Riddlr.PubSub,
          GameClock.topic(riddle.id),
          {:countdown_tick, :play, seconds}
        )

        render(live)
      end

      tick.(21)
      refute has_element?(live, ".rg-play.is-warn")
      refute has_element?(live, ".rg-play.is-crit")

      tick.(20)
      assert has_element?(live, ".rg-play.is-warn")

      tick.(11)
      assert has_element?(live, ".rg-play.is-warn")

      tick.(10)
      assert has_element?(live, ".rg-play.is-crit")
      refute has_element?(live, ".rg-play.is-warn")
    end

    test "every player takes the second from the riddle's clock", %{conn: conn, user: user} do
      live_date = ~U[2026-08-01 12:00:00.000000Z]

      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 60, live_date: live_date})
        |> set_play_status_direct("live")

      Frozen.freeze(live_date)
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      Phoenix.PubSub.broadcast(
        Riddlr.PubSub,
        GameClock.topic(riddle.id),
        {:countdown_tick, :play, 42}
      )

      assert has_element?(live, "#countdown-timer[data-seconds='42']")
    end

    test "the clock running out leaves no time on it", %{conn: conn, user: user} do
      live_date = ~U[2026-08-01 12:00:00.000000Z]

      riddle =
        GamesFixtures.riddle_fixture(%{solve_time: 60, live_date: live_date})
        |> set_play_status_direct("live")

      Frozen.freeze(live_date)
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      Phoenix.PubSub.broadcast(
        Riddlr.PubSub,
        GameClock.topic(riddle.id),
        {:countdown_tick, :play, 0}
      )

      assert has_element?(live, "#countdown-timer[data-seconds='0']")
    end
  end

  describe "solved count" do
    setup %{user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      %{riddle: riddle, user: user}
    end

    test "shows 0 solved before anyone solves", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#play-solved", "0 solved")
    end

    test "a player who arrives mid-round sees the current count", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      answer = hd(riddle.answers)
      {:correct, 1, _} = Gameplay.submit_answer(riddle, AccountsFixtures.user_fixture(), answer)
      {:correct, 2, _} = Gameplay.submit_answer(riddle, AccountsFixtures.user_fixture(), answer)
      :incorrect = Gameplay.submit_answer(riddle, AccountsFixtures.user_fixture(), "nope")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#play-solved", "2 solved")
    end

    test "goes up when another player solves", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      other = AccountsFixtures.user_fixture()
      {:correct, 1, _} = Gameplay.submit_answer(riddle, other, hd(riddle.answers))

      assert has_element?(live, "#play-solved", "1 solved")
    end

    test "a solver already counted is not counted again", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      other = AccountsFixtures.user_fixture()
      {:correct, 1, _} = Gameplay.submit_answer(riddle, other, hd(riddle.answers))

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # The same solve can arrive after the mount snapshot already counted it.
      solve = Answer.new(riddle.id, other, "keyboard", correct: true, placement: 1)
      Gameplay.broadcast_answer(solve)
      Gameplay.broadcast_answer(solve)

      assert has_element?(live, "#play-solved", "1 solved")
    end

    test "wrong guesses and chat leave the count alone", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      other = AccountsFixtures.user_fixture()
      :incorrect = Gameplay.submit_answer(riddle, other, "nope")
      Gameplay.broadcast_answer(Answer.new(riddle.id, other, "gg", chat: true))

      assert has_element?(live, "#feed-count", "2 guesses")
      assert has_element?(live, "#play-solved", "0 solved")
    end
  end

  describe "game state transitions via PubSub" do
    test "moves the player to results when the round ends", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:riddle_completed, riddle})

      assert_redirect(live, "/game/#{riddle.id}/results")
    end

    test "ignores :riddle_completed for a different riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      other = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:riddle_completed, other})

      assert has_element?(live, "#answer-form")
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

    test "a user banned before they arrived cannot submit an answer", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Riddlr.Accounts.set_user_status(user, :banned)

      riddle = GamesFixtures.riddle_fixture() |> set_play_status_direct("live")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      live
      |> form("#answer-form", %{answer: "keyboard"})
      |> render_submit()

      assert_redirect(live, "/")
      assert Gameplay.get_answers(riddle.id) == []
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

    test "shows a heading, a guess count and an empty state", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#feed-h", "Guesses")
      assert has_element?(live, "#feed-count", "0 guesses")

      assert has_element?(
               live,
               "#answer-feed .rg-feed__empty",
               "No guesses yet. Be the first to swing."
             )

      assert has_element?(live, "ol#answer-feed[aria-live='polite'][aria-relevant='additions']")

      send(live.pid, {:answer_submitted, Answer.new(riddle.id, user, "piano", offset_ms: 900)})
      assert has_element?(live, "#feed-count", "1 guess")
    end

    test "counts guesses already made before the player arrived", %{conn: conn, riddle: riddle} do
      other = AccountsFixtures.user_fixture()
      Frozen.freeze()
      :incorrect = Gameplay.submit_answer(riddle, other, "piano")
      Frozen.advance(1, :second)
      :incorrect = Gameplay.submit_answer(riddle, other, "organ")

      conn = log_in_user(conn, AccountsFixtures.user_fixture())
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#feed-count", "2 guesses")
    end

    test "a wrong guess shows struck through, and the viewer reads as you", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      other = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:answer_submitted, Answer.new(riddle.id, user, "piano", offset_ms: 900)})

      send(
        live.pid,
        {:answer_submitted, Answer.new(riddle.id, other, "organ", offset_ms: 65_000)}
      )

      render(live)

      assert has_element?(live, "#answer-feed .rg-msg.is-me.is-wrong .rg-msg__name", "you")
      assert has_element?(live, "#answer-feed .rg-msg.is-me .rg-msg__text", "piano")
      assert has_element?(live, "#answer-feed .rg-msg.is-wrong .rg-msg__name", other.username)
      assert has_element?(live, "#answer-feed .rg-msg .rg-tile--sm")
      assert has_element?(live, "#answer-feed .rg-msg__t", "+1:05")
    end

    test "new guesses go to the bottom of the feed", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      send(live.pid, {:answer_submitted, Answer.new(riddle.id, user, "piano", offset_ms: 900)})
      send(live.pid, {:answer_submitted, Answer.new(riddle.id, user, "organ", offset_ms: 1900)})
      render(live)

      assert has_element?(live, "#answer-feed .rg-msg:last-child", "organ")
    end

    test "the viewer's own solve shows as a stamp, never as text", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      Gameplay.broadcast_answer(
        Answer.new(riddle.id, user, "keyboard", correct: true, placement: 1)
      )

      assert has_element?(
               live,
               "#answer-feed .rg-msg.is-me.is-solve .rg-msg__stamp",
               "Solved · 1st"
             )

      refute render(live) =~ "keyboard"
    end

    test "submitted answer appears in the feed via PubSub", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      answer = Answer.new(riddle.id, user, "keyboard", offset_ms: 1_500)

      send(live.pid, {:answer_submitted, answer})

      html = render(live)
      assert html =~ user.username
      assert html =~ "keyboard"
    end

    test "a solve shows up in the feed as a placement, not as text", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      solver = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      Gameplay.broadcast_answer(
        Answer.new(riddle.id, solver, "keyboard", correct: true, placement: 2)
      )

      html = render(live)
      assert has_element?(live, "#answer-feed .rg-msg.is-solve", solver.username)
      assert has_element?(live, "#answer-feed .rg-msg__stamp", "Solved · 2nd")
      refute html =~ "keyboard"
    end

    test "a player joining mid-round never sees an already-solved answer", %{
      conn: conn,
      riddle: riddle
    } do
      solver = AccountsFixtures.user_fixture()
      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, solver, "keyboard")

      latecomer = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, latecomer)
      {:ok, _live, html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert html =~ solver.username
      refute html =~ "keyboard"
    end

    test "the replayed feed ranks solves in the order they happened", %{
      conn: conn,
      riddle: riddle
    } do
      first = AccountsFixtures.user_fixture()
      second = AccountsFixtures.user_fixture()
      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, first, "keyboard")
      assert {:correct, 2, 9} = Gameplay.submit_answer(riddle, second, "a keyboard")

      conn = log_in_user(conn, AccountsFixtures.user_fixture())
      {:ok, _live, html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert html =~ "1st"
      assert html =~ "2nd"
      refute html =~ "keyboard"
    end

    test "a flagged guess leaves the count", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      answer = Answer.new(riddle.id, user, "piano", offset_ms: 500)
      send(live.pid, {:answer_submitted, answer})
      assert has_element?(live, "#feed-count", "1 guess")

      send(live.pid, {:answer_flagged, answer.id})
      assert has_element?(live, "#feed-count", "0 guesses")
    end

    test "guesses made before the player arrived keep their time", %{
      conn: conn,
      user: user
    } do
      live_date = ~U[2026-08-01 12:00:00.000000Z]

      riddle =
        GamesFixtures.riddle_fixture(%{live_date: live_date})
        |> set_play_status_direct("live")

      Frozen.freeze(live_date)
      Frozen.advance(65, :second)
      :incorrect = Gameplay.submit_answer(riddle, AccountsFixtures.user_fixture(), "piano")

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      assert has_element?(live, "#answer-feed .rg-msg__t", "+1:05")
    end

    test "flagged answer is removed from the feed", %{conn: conn, riddle: riddle, user: user} do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # This exercises the retraction mechanism itself (:answer_flagged), the
      # hook the future external moderation layer fires — the local blocklist
      # no longer uses it, it masks synchronously before broadcast instead.
      answer = Answer.new(riddle.id, user, "clean content", offset_ms: 500)

      send(live.pid, {:answer_submitted, answer})
      html = render(live)
      assert html =~ "clean content"

      send(live.pid, {:answer_flagged, answer.id})
      html = render(live)
      refute html =~ "clean content"
    end

    test "submitting a blocked word masks it synchronously, never showing the raw word", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      # Inject the answer directly into the feed (simulates the PubSub broadcast
      # that handle_event sends). This is reliable in tests — the E2E PubSub
      # round-trip from form submit → PubSub → handle_info is async and would
      # require sleep() to stabilise.
      answer = Answer.new(riddle.id, user, @bad_word, offset_ms: 100)

      send(live.pid, {:answer_submitted, answer})

      html = render(live)
      refute html =~ @bad_word
      assert html =~ @mask
    end

    test "time offset is displayed for real-time answers", %{
      conn: conn,
      riddle: riddle,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/play")

      answer = Answer.new(riddle.id, user, "keyboard", offset_ms: 2_500)

      send(live.pid, {:answer_submitted, answer})

      assert has_element?(live, "#answer-feed .rg-msg__t", "+0:02")
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
