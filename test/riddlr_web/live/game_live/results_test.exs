defmodule RiddlrWeb.GameLive.ResultsTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Riddlr.Gameplay.Answer
  alias Riddlr.{Games, Gameplay, AccountsFixtures, GamesFixtures}
  alias Riddlr.Clock.Frozen
  alias RiddlrWeb.GameCopy

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user}
  end

  describe "mount" do
    test "renders the post-game screen for a completed riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      assert has_element?(
               live,
               ".rg-results__top .rg-kicker",
               "#{riddle.name} · #{riddle.category.name}"
             )

      assert has_element?(live, ".rg-results__riddle", riddle.description)
      assert has_element?(live, "#panel-board")
      assert has_element?(live, "#chat-form")
      refute has_element?(live, ".rg-round-header")
      refute has_element?(live, "#answer-form-container")
    end

    test "shows no status pill in the topbar", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      refute has_element?(live, ".rg-topbar__mid .rg-pill")
    end
  end

  describe "answer" do
    test "spells the riddle's first answer as tiles, grouped into one span per word", %{
      conn: conn,
      user: user
    } do
      riddle =
        GamesFixtures.riddle_fixture(%{answers: ["ice cap", "icecap"]})
        |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "h1.rg-answer[aria-label='Answer: ice cap']")
      assert has_element?(live, "h1.rg-answer[style*='--n: 3']")
      assert has_element?(live, ".rg-answer__w:nth-child(1) .rg-answer__l:nth-child(1)", "i")
      assert has_element?(live, ".rg-answer__w:nth-child(1) .rg-answer__l:nth-child(3)", "e")
      assert has_element?(live, ".rg-answer__w:nth-child(2) .rg-answer__l:nth-child(3)", "p")
      refute has_element?(live, ".rg-answer__w:nth-child(3)")
      refute has_element?(live, ".rg-answer__w .rg-answer__l:nth-child(4)")
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
      assert has_element?(live, "#res-by", GameCopy.solve_secs(3_456))
      assert has_element?(live, "#res-by", GameCopy.solved_count(2))
    end

    test "says you when the viewer cracked it first", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      GamesFixtures.solve_fixture(riddle, user, %{placement: 1, solve_time_ms: 12_000})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-by b", GameCopy.Lobby.room_you())
      assert has_element?(live, "#res-by", GameCopy.solve_secs(12_000))
      assert has_element?(live, "#res-by", GameCopy.solved_count(1))
    end

    test "says nobody cracked it when there are no solves", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-by", GameCopy.Results.results_unsolved())
    end
  end

  describe "you card" do
    test "a viewer who never guessed was not in this one", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      card = GameCopy.Results.you_card(nil, false)
      assert has_element?(live, "#res-you .rg-stamp.is-none", card.stamp)
      assert has_element?(live, "#res-you", card.title)
    end

    test "a viewer who guessed but did not solve", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      assert :incorrect = Gameplay.submit_answer(riddle, user, "banana")
      riddle = set_play_status(riddle, "completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      card = GameCopy.Results.you_card(nil, true)
      assert has_element?(live, "#res-you .rg-stamp.is-none", card.stamp)
      assert has_element?(live, "#res-you", card.title)
    end

    test "the viewer who won", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")
      GamesFixtures.solve_fixture(riddle, user, %{placement: 1, points: 10})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      card = GameCopy.Results.you_card(%{placement: 1, points: 10}, true)
      assert has_element?(live, "#res-you .rg-stamp:not(.is-none)", card.stamp)
      assert has_element?(live, "#res-you", card.title)
      assert has_element?(live, "#res-you", card.sub)
    end

    test "a viewer who placed outside the top 10", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")
      GamesFixtures.solve_fixture(riddle, user, %{placement: 11, points: 0})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      card = GameCopy.Results.you_card(%{placement: 11, points: 0}, true)
      assert has_element?(live, "#res-you .rg-stamp.is-none", card.stamp)
      assert has_element?(live, "#res-you", card.sub)
    end
  end

  describe "celebrate" do
    test "asks for a win when the riddle has a Solve, then drops the param", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      GamesFixtures.solve_fixture(riddle, AccountsFixtures.user_fixture())

      {:ok, live, _html} =
        live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results?celebrate=1")

      assert_patch(live, ~p"/game/#{riddle.id}/results")
      assert has_element?(live, "#celebrate[data-celebrate='win']")
    end

    test "asks for a loss when nobody solved the riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} =
        live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results?celebrate=1")

      assert_patch(live, ~p"/game/#{riddle.id}/results")
      assert has_element?(live, "#celebrate[data-celebrate='lose']")
    end

    test "a direct visit asks for nothing", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      GamesFixtures.solve_fixture(riddle, AccountsFixtures.user_fixture())

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#celebrate")
      refute has_element?(live, "#celebrate[data-celebrate]")
    end

    test "an archived riddle asks for nothing, even with the param", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("archived")
      GamesFixtures.solve_fixture(riddle, AccountsFixtures.user_fixture())

      {:ok, live, _html} =
        live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results?celebrate=1")

      assert_patch(live, ~p"/game/#{riddle.id}/results")
      refute has_element?(live, "#celebrate[data-celebrate]")
    end
  end

  describe "mount redirects" do
    test "lets a guest see the board and the chat", %{conn: conn} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      solver = AccountsFixtures.user_fixture()
      GamesFixtures.solve_fixture(riddle, solver)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")
      Gameplay.broadcast_answer(Answer.new(riddle.id, solver, "gg", chat: true))

      assert has_element?(live, ".rg-board .rg-row:not(.is-me)", solver.username)
      assert has_element?(live, "#chat-feed li.rg-msg:not(.is-me)", "gg")
    end

    test "does not show a deleted player's solve as a guest's own", %{conn: conn} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      gone = AccountsFixtures.user_fixture()
      GamesFixtures.solve_fixture(riddle, gone)
      Riddlr.Repo.delete!(gone)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-board .rg-row", GameCopy.gone_player())
      refute has_element?(live, ".is-me")
    end

    test "gives a guest the join note, no you card and no chat form", %{conn: conn} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#join-note a[href='/users/log-in']")
      refute has_element?(live, "#res-you")
      refute has_element?(live, "#chat-form")
    end

    test "ignores a chat message sent by a guest", %{conn: conn} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(riddle.id))

      render_hook(live, "send_chat", %{"message" => "sneaky"})

      refute_receive {:answer_submitted, _}
      refute has_element?(live, "#chat-feed", "sneaky")
    end

    test "gives a signed-in player the you card and chat form, no join note", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-you")
      assert has_element?(live, "#chat-form")
      refute has_element?(live, "#join-note")
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

      assert has_element?(live, ".rg-podium > .rg-pod--2:nth-child(1)", GameCopy.Lobby.room_you())
      assert has_element?(live, ".rg-podium > .rg-pod--1:nth-child(2)", winner.username)
      assert has_element?(live, ".rg-pod--1 .rg-pod__t", GameCopy.solve_secs(3_000))
      assert has_element?(live, ".rg-pod--1 .rg-pod__pts", "+10")
      assert has_element?(live, ".rg-pod--2 .rg-pod__t", GameCopy.solve_secs(61_000))

      assert has_element?(
               live,
               ".rg-podium > .rg-pod--3.rg-pod--empty:nth-child(3)",
               GameCopy.Results.podium_open()
             )
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

      assert has_element?(
               live,
               "ol.rg-board > li.rg-row.is-me:nth-child(2) .rg-row__name",
               GameCopy.Lobby.room_you()
             )

      assert has_element?(
               live,
               "ol.rg-board > li.rg-row.is-me:nth-child(2) .rg-row__t",
               GameCopy.solve_secs(4_250)
             )

      refute has_element?(live, "ol.rg-board > li.rg-row.is-me:nth-child(1)")
    end

    # The medal colours hang off the Podium place classes and the first
    # three board rows, so those must hold places 1–3 in order.
    test "fills places 1–3 on the Podium and the first three board rows", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      first = AccountsFixtures.user_fixture()
      second = AccountsFixtures.user_fixture()
      GamesFixtures.solve_fixture(riddle, first, %{placement: 1, solve_time_ms: 3_000})
      GamesFixtures.solve_fixture(riddle, second, %{placement: 2, solve_time_ms: 4_000})
      GamesFixtures.solve_fixture(riddle, user, %{placement: 3, solve_time_ms: 5_000})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      refute has_element?(live, ".rg-pod--empty")
      assert has_element?(live, ".rg-pod--1 .rg-pod__name", first.username)
      assert has_element?(live, ".rg-pod--2 .rg-pod__name", second.username)
      assert has_element?(live, ".rg-pod--3 .rg-pod__name", GameCopy.Lobby.room_you())

      for place <- 1..3 do
        assert has_element?(
                 live,
                 "ol.rg-board > li.rg-row:nth-child(#{place}) .rg-row__place",
                 "#{place}"
               )
      end

      assert has_element?(live, "ol.rg-board > li.rg-row.is-me:nth-child(3)")
      assert has_element?(live, ".rg-pt.is-taken.is-me:nth-child(3)")
    end
  end

  describe "payout" do
    test "shows ten places with points and who claimed them", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      winner = AccountsFixtures.user_fixture()
      GamesFixtures.solve_fixture(riddle, winner, %{placement: 1, points: 10})
      GamesFixtures.solve_fixture(riddle, user, %{placement: 2, points: 9})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, ".rg-payout .rg-panel__h")
      assert has_element?(live, ".rg-points__row > .rg-pt.is-taken:nth-child(1)", winner.username)
      assert has_element?(live, ".rg-pt:nth-child(1) .rg-pt__p", GameCopy.ordinal(1))
      assert has_element?(live, ".rg-pt:nth-child(1) .rg-pt__v", "10")

      assert has_element?(
               live,
               ".rg-pt.is-taken.is-me:nth-child(2) .rg-pt__who",
               GameCopy.Lobby.room_you()
             )

      assert has_element?(
               live,
               ".rg-pt.is-open:nth-child(3) .rg-pt__who",
               GameCopy.Results.payout_unclaimed()
             )

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
               "#tab-board[role=tab][aria-controls=panel-board][aria-selected=true]"
             )

      assert has_element?(
               live,
               "#tab-chat[role=tab][aria-controls=panel-chat][aria-selected=false][tabindex='-1']"
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

      assert has_element?(
               live,
               "#chat-feed li.rg-msg.is-solve .rg-msg__stamp",
               GameCopy.Play.feed_solved(1)
             )

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

      assert has_element?(
               live,
               "ol#chat-feed > li.rg-chat__div[role=separator]",
               GameCopy.Results.chat_divider()
             )

      assert has_element?(live, "#chat-feed li.rg-msg.is-wrong .rg-msg__text", "banana")
      assert position(html, "banana") < position(html, GameCopy.Results.chat_divider())
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

      assert position(html, GameCopy.Results.chat_divider()) < position(html, "gg everyone")
    end
  end

  describe "post-game chat" do
    test "has a labelled message field and an icon send button", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#chat-form label.rg-sr-only[for=chat-input]")

      assert has_element?(
               live,
               "#chat-form input#chat-input[placeholder='#{GameCopy.Results.chat_placeholder()}']"
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

      assert has_element?(
               live,
               "#chat-feed li.rg-msg.is-me .rg-msg__name",
               GameCopy.Lobby.room_you()
             )

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

    test "a second message inside a second is dropped", %{conn: conn, user: user} do
      Frozen.freeze()
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      render_submit(element(live, "#chat-form"), %{"message" => "gg everyone"})
      render_submit(element(live, "#chat-form"), %{"message" => "spam"})

      assert has_element?(live, "#chat-feed", "gg everyone")
      refute has_element?(live, "#chat-feed", "spam")
    end

    test "a user banned before they arrived sees results as a guest, with no chat form", %{
      conn: conn
    } do
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Riddlr.Accounts.set_user_status(user, :banned)

      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      refute has_element?(live, "#chat-form")
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
    test "links to the Standings", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next a[href='/standings']")
    end

    test "says nothing is scheduled when there is no next riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next", GameCopy.Results.next_none())
      assert has_element?(live, "#res-next a[href='/']")
      refute has_element?(live, "#res-next .rg-btn")
    end

    test "sends players to the lobby of a ready riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      live_date = ~U[2030-01-01 14:05:00Z]
      next = upcoming_fixture("ready", live_date)

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next .rg-next__t b", next.category.name)

      assert has_element?(
               live,
               "#res-next time[datetime='2030-01-01T14:05:00Z']",
               "Jan 1, 9:05am EST"
             )

      assert has_element?(live, "#res-next .rg-drop-local[hidden]")

      assert has_element?(live, "#res-next a.rg-btn[href='/game/#{next.id}/lobby']")

      assert has_element?(live, "#res-next a[href='/']")
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
      assert has_element?(live, "#res-next time", "Jan 1, 9:05am EST")
      refute has_element?(live, "#res-next .rg-btn")
      assert has_element?(live, "#res-next a[href='/']")
    end

    test "sends players straight into a live riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      next = upcoming_fixture("live", ~U[2020-01-01 14:05:00Z])

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#res-next .rg-next__t b", "#{next.number}")
      assert has_element?(live, "#res-next .rg-next__t", next.category.name)
      assert has_element?(live, "#res-next .rg-next__t", GameCopy.Results.next_live_now())
      refute has_element?(live, "#res-next time")

      assert has_element?(live, "#res-next a.rg-btn[href='/game/#{next.id}/play']")
    end

    test "switches to Jump in when the next riddle goes live", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")
      assert has_element?(live, "#res-next a.rg-btn[href='/game/#{next.id}/lobby']")

      {:ok, _} = Games.transition(next.id, :live)

      assert has_element?(live, "#res-next a.rg-btn[href='/game/#{next.id}/play']")
    end

    test "shows a riddle scheduled while the viewer is on the page", %{
      conn: conn,
      user: user
    } do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")
      assert has_element?(live, "#res-next", GameCopy.Results.next_none())

      next = GamesFixtures.scheduled_riddle_fixture()

      assert has_element?(live, "#res-next .rg-next__t b", next.category.name)
    end
  end

  describe "chat countdown" do
    setup do
      now = ~U[2026-08-01 12:00:00Z]
      Frozen.freeze(now)
      %{now: now}
    end

    test "a completed riddle counts down to Archive above the chat form", %{
      conn: conn,
      user: user,
      now: now
    } do
      # Went live 60s ago with a 60s solve time, so it archives 180s from now.
      riddle = finished_fixture(now, -60, archive_after_seconds: 180)

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      archive_at = now |> DateTime.add(180, :second) |> DateTime.to_iso8601()

      assert has_element?(
               live,
               "#chat-countdown[phx-hook][data-archive-at='#{archive_at}']",
               GameCopy.Results.chat_closes_in(180)
             )

      assert has_element?(live, "#chat-countdown + #chat-foot #chat-form")
    end

    test "says closing, not a negative time, once the archive time has passed", %{
      conn: conn,
      user: user,
      now: now
    } do
      # Archive was due 60s ago, but its broadcast has not arrived.
      riddle = finished_fixture(now, -300, archive_after_seconds: 180)

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#chat-countdown", GameCopy.Results.chat_closing())
      refute has_element?(live, "#chat-countdown", "-")
    end

    test "an archived riddle shows no countdown", %{conn: conn, user: user, now: now} do
      riddle =
        finished_fixture(now, -60, archive_after_seconds: 180) |> set_play_status("archived")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      refute has_element?(live, "#chat-countdown")
      assert has_element?(live, "#chat-empty", GameCopy.Results.chat_archived())
    end

    test "a riddle with no archive delay shows no countdown", %{
      conn: conn,
      user: user,
      now: now
    } do
      # With no delay, Archive follows completion at once.
      riddle = finished_fixture(now, -60, archive_after_seconds: 0) |> set_play_status("archived")

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      refute has_element?(live, "#chat-countdown")
    end

    test "Archive disables the form, shows an emoji and keeps the feed", %{
      conn: conn,
      user: user,
      now: now
    } do
      riddle = finished_fixture(now, -60, archive_after_seconds: 180)
      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      Gameplay.broadcast_answer(Answer.new(riddle.id, user, "well played", chat: true))
      send(live.pid, {:riddle_archived, riddle})

      refute has_element?(live, "#chat-countdown")
      assert has_element?(live, "#chat-foot.is-closed #chat-input[disabled]")
      assert has_element?(live, "#chat-foot.is-closed button[type=submit][disabled]")

      assert Enum.any?(
               GameCopy.Results.chat_closed_emojis(),
               &has_element?(live, "#chat-foot #chat-closed-emoji", &1)
             )

      # The text sits left of the emoji, and screen readers get only the text.
      assert has_element?(
               live,
               "#chat-closed-emoji > .rg-chat__closed-text:first-child",
               GameCopy.Results.chat_closed()
             )

      assert has_element?(live, "#chat-closed-emoji > [aria-hidden=true]:last-child")

      assert has_element?(live, "#chat-feed", "well played")
      refute has_element?(live, "#chat-empty")
      assert has_element?(live, "#flash-info")
    end

    test "send_chat after Archive does not broadcast", %{conn: conn, user: user, now: now} do
      riddle = finished_fixture(now, -60, archive_after_seconds: 180)
      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(riddle.id))

      send(live.pid, {:riddle_archived, riddle})
      # A stale client can still push the event after the form is disabled.
      render_hook(live, "send_chat", %{"message" => "too late"})

      refute_receive {:answer_submitted, _answer}
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
      assert has_element?(live, "#chat-feed > li.rg-chat__div", GameCopy.Results.chat_divider())

      assert has_element?(
               live,
               "#chat-feed > li.rg-chat__empty",
               GameCopy.Results.chat_archived()
             )
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
               GameCopy.Results.board_empty()
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

      assert has_element?(live, "#flash-info")
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

  # A completed riddle that went live `live_in` seconds from `now` (negative
  # for the past), with a 60s solve time.
  defp finished_fixture(now, live_in, attrs) do
    GamesFixtures.riddle_fixture(Map.new(attrs))
    |> Ecto.Changeset.change(
      play_status: "completed",
      live_date: DateTime.add(now, live_in, :second)
    )
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
