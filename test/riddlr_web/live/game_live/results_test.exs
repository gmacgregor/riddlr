defmodule RiddlrWeb.GameLive.ResultsTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.Gameplay.Answer
  alias Riddlr.{Games, Gameplay, AccountsFixtures, GamesFixtures}

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user}
  end

  describe "mount" do
    test "renders the post-game screen for a completed riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-results__top .rg-kicker", riddle.category.name)
      assert has_element?(live, ".rg-results__riddle", "“#{riddle.description}”")
      assert has_element?(live, "#panel-board")
      assert has_element?(live, "#chat-form")
      refute has_element?(live, ".rg-round-header")
      refute has_element?(live, "#answer-form-container")
    end
  end

  describe "answer" do
    test "spells the riddle's first answer as tiles, with a gap for each space", %{
      conn: conn,
      user: user
    } do
      riddle =
        GamesFixtures.riddle_fixture(%{answers: ["ice cap", "icecap"]})
        |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "h1.rg-answer[aria-label='Answer: ice cap']")
      assert has_element?(live, ".rg-answer .rg-answer__l:nth-child(1)", "i")
      assert has_element?(live, ".rg-answer .rg-answer__l:nth-child(3)", "e")
      assert has_element?(live, ".rg-answer .rg-answer__gap:nth-child(4)")
      assert has_element?(live, ".rg-answer .rg-answer__l:nth-child(7)", "p")
      refute has_element?(live, ".rg-answer :nth-child(8)")
    end

    test "shows dark tiles when nobody solved", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-answer.is-unsolved")
    end

    test "shows light tiles once someone solved", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      GamesFixtures.solve_fixture(riddle, AccountsFixtures.user_fixture())

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-answer")
      refute has_element?(live, ".rg-answer.is-unsolved")
    end
  end

  describe "by line" do
    test "names the first solver, their time and the solve count", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      winner = AccountsFixtures.user_fixture()
      GamesFixtures.solve_fixture(riddle, winner, %{placement: 1, solve_time_ms: 3_456})
      GamesFixtures.solve_fixture(riddle, user, %{placement: 2, points: 9, solve_time_ms: 9_000})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-by b", winner.username)
      assert has_element?(live, "#res-by", "in 3.46s · 2 solved")
    end

    test "says you when the viewer cracked it first", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      GamesFixtures.solve_fixture(riddle, user, %{placement: 1, solve_time_ms: 12_000})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-by b", "you")
      assert has_element?(live, "#res-by", "in 12.00s · 1 solved")
    end

    test "says nobody cracked it when there are no solves", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-by", "Nobody cracked it before the clock ran out.")
    end
  end

  describe "you card" do
    test "a viewer who never guessed was not in this one", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-you .rg-stamp.is-none", "—")
      assert has_element?(live, "#res-you", "You weren't in this one")
    end

    test "a viewer who guessed but did not solve", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      assert :incorrect = Gameplay.submit_answer(riddle, user, "banana")
      riddle = set_play_status(riddle, "completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-you .rg-stamp.is-none", "0")
      assert has_element?(live, "#res-you", "Not this time")
    end

    test "the viewer who won", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")
      GamesFixtures.solve_fixture(riddle, user, %{placement: 1, points: 10})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-you .rg-stamp:not(.is-none)", "1ST")
      assert has_element?(live, "#res-you", "You won it")
      assert has_element?(live, "#res-you", "+10 pts for this riddle")
    end

    test "a viewer who placed outside the top 10", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")
      GamesFixtures.solve_fixture(riddle, user, %{placement: 11, points: 0})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-you .rg-stamp.is-none", "11TH")
      assert has_element?(live, "#res-you", "Solved, but outside the top 10.")
    end
  end

  describe "mount redirects" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/game/#{riddle.id}/results")
    end

    test "redirects home when the riddle does not exist", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/game/999999/results")
    end

    for status <- ["closed", "scheduled", "ready"] do
      test "redirects to the lobby when the riddle is #{status}", %{conn: conn, user: user} do
        riddle = GamesFixtures.riddle_fixture() |> set_play_status(unquote(status))
        conn = log_in_user(conn, user)

        assert {:error, {:live_redirect, %{to: path}}} =
                 live(conn, ~p"/game/#{riddle.id}/results")

        assert path == "/game/#{riddle.id}/lobby"
      end
    end

    test "redirects to play when the riddle is live", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/game/#{riddle.id}/results")

      assert path == "/game/#{riddle.id}/play"
    end
  end

  describe "podium" do
    test "orders the top three 2 · 1 · 3 with time and points", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      winner = AccountsFixtures.user_fixture()

      GamesFixtures.solve_fixture(riddle, winner, %{
        placement: 1,
        points: 10,
        solve_time_ms: 3_000
      })

      GamesFixtures.solve_fixture(riddle, user, %{placement: 2, points: 9, solve_time_ms: 61_000})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-podium > .rg-pod--2:nth-child(1)", "you")
      assert has_element?(live, ".rg-podium > .rg-pod--1:nth-child(2)", winner.username)
      assert has_element?(live, ".rg-pod--1 .rg-pod__t", "3.00s")
      assert has_element?(live, ".rg-pod--1 .rg-pod__pts", "+10")
      assert has_element?(live, ".rg-pod--2 .rg-pod__t", "61.00s")
      assert has_element?(live, ".rg-podium > .rg-pod--3.rg-pod--empty:nth-child(3)", "Open")
    end

    test "leaves every slot open when nobody solved", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-pod--1.rg-pod--empty")
      assert has_element?(live, ".rg-pod--2.rg-pod--empty")
      assert has_element?(live, ".rg-pod--3.rg-pod--empty")
    end
  end

  describe "board" do
    test "lists every solve with place, name, time and points", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      winner = AccountsFixtures.user_fixture()
      GamesFixtures.solve_fixture(riddle, winner, %{placement: 1, solve_time_ms: 3_000})
      GamesFixtures.solve_fixture(riddle, user, %{placement: 2, points: 9, solve_time_ms: 4_250})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "ol.rg-board > li.rg-row:nth-child(1) .rg-row__place", "1")

      assert has_element?(
               live,
               "ol.rg-board > li.rg-row:nth-child(1) .rg-row__name",
               winner.username
             )

      assert has_element?(live, "ol.rg-board > li.rg-row:nth-child(1) .rg-row__pts", "+10")
      assert has_element?(live, "ol.rg-board > li.rg-row.is-me:nth-child(2) .rg-row__name", "you")
      assert has_element?(live, "ol.rg-board > li.rg-row.is-me:nth-child(2) .rg-row__t", "4.25s")
      refute has_element?(live, "ol.rg-board > li.rg-row.is-me:nth-child(1)")
    end
  end

  describe "payout" do
    test "shows ten places with points and who claimed them", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      winner = AccountsFixtures.user_fixture()
      GamesFixtures.solve_fixture(riddle, winner, %{placement: 1, points: 10})
      GamesFixtures.solve_fixture(riddle, user, %{placement: 2, points: 9})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-payout .rg-panel__h", "Points this riddle")
      assert has_element?(live, ".rg-points__row > .rg-pt.is-taken:nth-child(1)", winner.username)
      assert has_element?(live, ".rg-pt:nth-child(1) .rg-pt__p", "1st")
      assert has_element?(live, ".rg-pt:nth-child(1) .rg-pt__v", "10")
      assert has_element?(live, ".rg-pt.is-taken.is-me:nth-child(2) .rg-pt__who", "you")
      assert has_element?(live, ".rg-pt.is-open:nth-child(3) .rg-pt__who", "unclaimed")
      assert has_element?(live, ".rg-pt.is-open:nth-child(10) .rg-pt__v", "1")
      refute has_element?(live, ".rg-pt:nth-child(11)")
    end
  end

  describe "tabs" do
    test "start on Leaderboard, with Chat off and its badge hidden", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#results-tabs[role=tablist][aria-label=Results]")

      assert has_element?(
               live,
               "#tab-board[role=tab][aria-controls=panel-board][aria-selected=true]",
               "Leaderboard"
             )

      assert has_element?(
               live,
               "#tab-chat[role=tab][aria-controls=panel-chat][aria-selected=false][tabindex='-1']",
               "Chat"
             )

      assert has_element?(live, "#tab-chat #chat-badge.rg-tab__badge[hidden]")
      refute has_element?(live, "#panel-board.is-off")
      assert has_element?(live, "#panel-chat.is-off")
      refute has_element?(live, "#panel-chat[hidden]")
    end
  end

  describe "post-game feed" do
    test "reveals the answers that were masked during the round", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      solver = AccountsFixtures.user_fixture()
      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, solver, "keyboard")

      riddle = set_play_status(riddle, "completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#chat-feed li.rg-msg.is-solve .rg-msg__stamp", "Solved · 1st")
      assert has_element?(live, "#chat-feed li.rg-msg.is-solve .rg-msg__text", "keyboard")
    end

    test "keeps the round's guesses above a round-ended divider", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      guesser = AccountsFixtures.user_fixture()
      assert :incorrect = Gameplay.submit_answer(riddle, guesser, "banana")

      riddle = set_play_status(riddle, "completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")
      html = render(live)

      assert has_element?(live, "ol#chat-feed > li.rg-chat__div[role=separator]", "Riddle ended")
      assert has_element?(live, "#chat-feed li.rg-msg.is-wrong .rg-msg__text", "banana")
      assert position(html, "banana") < position(html, "Riddle ended")
    end

    test "lists the guess log oldest first", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      first = AccountsFixtures.user_fixture()
      second = AccountsFixtures.user_fixture()
      assert :incorrect = Gameplay.submit_answer(riddle, first, "banana")
      assert :incorrect = Gameplay.submit_answer(riddle, second, "cabbage")

      riddle = set_play_status(riddle, "completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")
      html = render(live)

      assert position(html, "banana") < position(html, "cabbage")
    end

    test "a message sent after the round renders below the divider", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      send(live.pid, {:answer_submitted, Answer.new(riddle.id, user, "gg everyone", chat: true)})
      html = render(live)

      assert position(html, "Riddle ended") < position(html, "gg everyone")
    end
  end

  describe "post-game chat" do
    test "has a labelled message field and an icon send button", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#chat-form label.rg-sr-only[for=chat-input]", "Message")

      assert has_element?(
               live,
               "#chat-form input#chat-input[placeholder='Say something nice to the winner']"
             )

      assert has_element?(
               live,
               "#chat-form button.rg-btn.rg-btn--icon[type=submit][aria-label='Send message'] svg"
             )
    end

    test "shows a message as a tile, a name and the text", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      other = AccountsFixtures.user_fixture()

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      Gameplay.broadcast_answer(Answer.new(riddle.id, user, "gg everyone", chat: true))
      Gameplay.broadcast_answer(Answer.new(riddle.id, other, "well played", chat: true))

      assert has_element?(live, "#chat-feed li.rg-msg.is-chat.is-me .rg-tile")
      assert has_element?(live, "#chat-feed li.rg-msg.is-me .rg-msg__name", "you")
      assert has_element?(live, "#chat-feed li.rg-msg.is-me .rg-msg__text", "gg everyone")
      assert has_element?(live, "#chat-feed li.rg-msg:not(.is-me) .rg-msg__name", other.username)
      refute has_element?(live, "#chat-feed .rg-msg__t")
    end

    test "a flagged message leaves the feed", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      message = Answer.new(riddle.id, user, "clean content", chat: true)
      Gameplay.broadcast_answer(message)
      assert has_element?(live, "#chat-feed", "clean content")

      Phoenix.PubSub.broadcast(
        Riddlr.PubSub,
        Answer.flagged_topic(riddle.id),
        {:answer_flagged, message.id}
      )

      refute has_element?(live, "#chat-feed", "clean content")
    end

    test "an empty message tells the client to refocus the input", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      render_submit(element(live, "#chat-form"), %{"message" => "   "})

      assert_push_event(live, "chat-empty", %{})
      refute has_element?(live, "#chat-feed .rg-msg")
    end

    test "sending a message tells the client to clear the input", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      render_submit(element(live, "#chat-form"), %{"message" => "gg everyone"})

      assert_push_event(live, "chat-sent", %{})
    end

    test "a sent message reaches the feed", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      render_submit(element(live, "#chat-form"), %{"message" => "gg everyone"})

      assert has_element?(live, "#chat-feed", "gg everyone")
    end

    test "a user banned before they arrived cannot chat", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Riddlr.Accounts.set_user_status(user, :banned)

      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      render_submit(element(live, "#chat-form"), %{"message" => "hello"})

      assert_redirect(live, "/")
    end

    test "a ban sends the player home", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      send(live.pid, {:user_status_changed, :banned})

      assert_redirect(live, "/")
    end
  end

  describe "next riddle card" do
    test "says nothing is scheduled when there is no next riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next", "No riddle on the schedule yet.")
      assert has_element?(live, "#res-next a[href='/']", "Back to home")
      refute has_element?(live, "#res-next .rg-btn")
    end

    test "sends players to the lobby of a ready riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      live_date = ~U[2030-01-01 14:05:00Z]
      next = upcoming_fixture("ready", live_date)

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next .rg-next__t b", next.category.name)
      assert has_element?(live, "#res-next time[datetime='2030-01-01T14:05:00Z']", "14:05")

      assert has_element?(
               live,
               "#res-next a.rg-btn[href='/game/#{next.id}/lobby']",
               "Enter the lobby"
             )

      assert has_element?(live, "#res-next a[href='/']", "Back to home")
    end

    # The Lobby opens only once a riddle is ready, so a button would bounce
    # the player home.
    test "shows a scheduled riddle's start time with no lobby button", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      next = upcoming_fixture("scheduled", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next .rg-next__t b", next.category.name)
      assert has_element?(live, "#res-next time", "14:05")
      refute has_element?(live, "#res-next .rg-btn")
      assert has_element?(live, "#res-next a[href='/']", "Back to home")
    end

    test "sends players straight into a live riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      next = upcoming_fixture("live", ~U[2020-01-01 14:05:00Z])

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next .rg-next__t b", "No. #{next.number}")
      assert has_element?(live, "#res-next .rg-next__t", "#{next.category.name} · live now")
      refute has_element?(live, "#res-next time")

      assert has_element?(
               live,
               "#res-next a.rg-btn[href='/game/#{next.id}/play']",
               "Jump in"
             )
    end

    test "switches to Jump in when the next riddle goes live", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")
      assert has_element?(live, "#res-next a.rg-btn", "Enter the lobby")

      {:ok, _} = Games.transition(next.id, :live)

      assert has_element?(live, "#res-next a.rg-btn[href='/game/#{next.id}/play']", "Jump in")
    end

    test "shows a riddle scheduled while the viewer is on the page", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")
      assert has_element?(live, "#res-next", "No riddle on the schedule yet.")

      next = GamesFixtures.scheduled_riddle_fixture()

      assert has_element?(live, "#res-next .rg-next__t b", next.category.name)
    end
  end

  describe "archive" do
    test "shows the saved board for an archived riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")
      winner = AccountsFixtures.user_fixture()

      GamesFixtures.solve_fixture(riddle, winner, %{
        placement: 1,
        points: 10,
        solve_time_ms: 3_000
      })

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-results__top")
      assert has_element?(live, "#panel-board .rg-row", winner.username)
      refute has_element?(live, "#chat-feed .rg-msg")
      assert has_element?(live, "#chat-feed > li.rg-chat__div", "Riddle ended")
      assert has_element?(live, "#chat-feed > li.rg-chat__empty", "Chat closed")
    end

    test "takes no chat once archived", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      refute has_element?(live, "#chat-form")

      Gameplay.broadcast_answer(Answer.new(riddle.id, user, "late message", chat: true))
      render_hook(live, "send_chat", %{"message" => "sneaky"})

      refute has_element?(live, "#chat-feed", "late message")
      refute has_element?(live, "#chat-feed", "sneaky")
    end

    test "shows an empty board when nobody solved", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(
               live,
               "#panel-board .rg-board__empty",
               "The board is empty. The riddle wins this round."
             )

      refute has_element?(live, "#panel-board .rg-row")
    end

    test "stays on the page and shows a flash when the riddle is archived", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      send(live.pid, {:riddle_archived, riddle})

      assert render(live) =~ "This game has been archived."
      assert has_element?(live, ".rg-results__top")
    end
  end

  # Sets play_status directly, skipping the changeset's transition checks.
  defp set_play_status(riddle, new_status) do
    riddle
    |> Ecto.Changeset.change(play_status: new_status)
    |> Riddlr.Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end

  # A published riddle in `play_status` that goes live at `live_date`.
  defp upcoming_fixture(play_status, live_date) do
    GamesFixtures.riddle_fixture()
    |> Ecto.Changeset.change(
      play_status: play_status,
      publish_status: "published",
      live_date: live_date
    )
    |> Riddlr.Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end

  # Byte offset of `text` in rendered HTML, for asserting one row sits above another.
  defp position(html, text), do: html |> :binary.match(text) |> elem(0)
end
