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

      assert has_element?(live, ".rg-round-header")
      assert has_element?(live, "#panel-leaderboard")
      assert has_element?(live, "#chat-form")
      refute has_element?(live, "#answer-form-container")
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

  describe "leaderboard" do
    test "shows the saved solves of a completed riddle", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      winner = AccountsFixtures.user_fixture()

      GamesFixtures.solve_fixture(riddle, winner, %{
        placement: 1,
        points: 10,
        solve_time_ms: 3_000
      })

      GamesFixtures.solve_fixture(riddle, user, %{placement: 2, points: 9, solve_time_ms: 61_000})

      {:ok, live, _html} = live(log_in_user(conn, user), ~p"/game/#{riddle.id}/results")

      assert has_element?(live, "#panel-leaderboard .rg-podium__card--gold", winner.username)
      assert has_element?(live, "#panel-leaderboard .rg-podium__card--gold", "+00:03")
      assert has_element?(live, "#panel-leaderboard .rg-podium__card--silver", user.username)
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

      assert has_element?(live, "#panel-chat .rg-solve-badge", "solved it — 1st: keyboard")
    end

    test "keeps the round's guesses below a round-ended divider", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      guesser = AccountsFixtures.user_fixture()
      assert :incorrect = Gameplay.submit_answer(riddle, guesser, "banana")

      riddle = set_play_status(riddle, "completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")
      html = render(live)

      assert has_element?(live, "#panel-chat .rg-post-chat-divider", "Round ended")
      assert has_element?(live, "#panel-chat", "banana")
      assert position(html, "Round ended") < position(html, "banana")
    end

    test "keeps the live feed's newest-first order", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("live")
      first = AccountsFixtures.user_fixture()
      second = AccountsFixtures.user_fixture()
      assert :incorrect = Gameplay.submit_answer(riddle, first, "banana")
      assert :incorrect = Gameplay.submit_answer(riddle, second, "cabbage")

      riddle = set_play_status(riddle, "completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")
      html = render(live)

      assert position(html, "cabbage") < position(html, "banana")
    end

    test "a message sent after the round renders above the divider", %{conn: conn, user: user} do
      riddle = GamesFixtures.riddle_fixture() |> set_play_status("completed")
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/game/#{riddle.id}/results")

      send(live.pid, {:answer_submitted, Answer.new(riddle.id, user, "gg everyone", chat: true)})
      html = render(live)

      assert position(html, "gg everyone") < position(html, "Round ended")
    end
  end

  describe "post-game chat" do
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

      assert has_element?(live, ".rg-round-header")
      assert has_element?(live, "#panel-leaderboard .rg-podium__card--gold", winner.username)
      refute has_element?(live, "#chat-feed .rg-post-chat-msg")
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

      assert has_element?(live, "#panel-leaderboard")
      refute has_element?(live, "#panel-leaderboard .rg-podium")
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
      assert has_element?(live, ".rg-round-header")
    end
  end

  # Sets play_status directly, skipping the changeset's transition checks.
  defp set_play_status(riddle, new_status) do
    riddle
    |> Ecto.Changeset.change(play_status: new_status)
    |> Riddlr.Repo.update!()
    |> then(&Games.get_riddle!(&1.id))
  end

  # Byte offset of `text` in rendered HTML, for asserting one row sits above another.
  defp position(html, text), do: html |> :binary.match(text) |> elem(0)
end
