defmodule RiddlrWeb.HomeLiveTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures

  alias Riddlr.Clock.Frozen
  alias Riddlr.{Gameplay, Games, GamesFixtures}
  alias Riddlr.Gameplay.Presence

  describe "hero and intro" do
    test "shows the hero and the intro to a logged-out visitor", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "h1#home-h", "One riddle.")
      assert has_element?(live, "h1#home-h", "Everyone at once.")
      assert has_element?(live, "h1#home-h em", "First to crack it wins.")
      assert has_element?(live, "#intro h2", "First time here?")
      assert has_element?(live, "#intro li:nth-child(1) .rg-tile[data-tone='hi']", "1")
      assert has_element?(live, "#intro li:nth-child(1) .rg-intro__t", "Join the lobby")

      assert has_element?(
               live,
               "#intro li:nth-child(1) .rg-intro__s",
               "Each riddle drops at a set time. Wait in the lobby with everyone else."
             )

      assert has_element?(live, "#intro li:nth-child(2) .rg-intro__t", "Race to answer")

      assert has_element?(
               live,
               "#intro li:nth-child(2) .rg-intro__s",
               "The riddle appears for all players at once. Guess as often as you like."
             )

      assert has_element?(live, "#intro li:nth-child(3) .rg-tile", "3")
      assert has_element?(live, "#intro li:nth-child(3) .rg-intro__t", "Beat the clock")

      assert has_element?(
               live,
               "#intro li:nth-child(3) .rg-intro__s",
               "The ten fastest correct answers score, from 10 points down to 1."
             )
    end

    test "shows the hero and the intro to a logged-in player", %{conn: conn} do
      {:ok, live, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")

      assert has_element?(live, "h1#home-h em", "First to crack it wins.")
      assert has_element?(live, "#intro h2", "First time here?")
    end
  end

  describe "hero card" do
    test "says nothing is scheduled when there is no next riddle", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card", "No riddle on the schedule yet.")
      refute has_element?(live, "#hero-card .rg-btn")
    end

    test "shows a live riddle's time left and solves, and links to Play", %{conn: conn} do
      live_date = ~U[2030-01-01 14:05:00Z]
      Frozen.freeze(DateTime.add(live_date, 10, :second))
      next = upcoming_fixture("live", live_date)
      {:correct, 1, _} = Gameplay.submit_answer(next, user_fixture(), "keyboard")

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card.is-live")
      assert has_element?(live, "#hero-card .rg-hero__label", "Live now · #{next.category.name}")
      assert has_element?(live, "#hero-card .rg-pill--live .rg-live-dot")
      assert has_element?(live, "#hero-left", "0:50")
      assert has_element?(live, "#hero-card .rg-pill--live", "left")
      assert has_element?(live, "#hero-card .rg-hero__teaser", "The race is on. 1 solved so far.")
      refute has_element?(live, "#hero-flaps")

      assert has_element?(
               live,
               "#hero-card a.rg-btn[href='/game/#{next.id}/play']",
               "Jump in"
             )
    end

    test "counts down to a ready riddle and links to its lobby", %{conn: conn} do
      now = ~U[2030-01-01 14:03:30.000000Z]
      Frozen.freeze(now)
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      track_player(next, 7, "ada")

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card .rg-hero__label", "#{next.category.name} · drops at")
      assert has_element?(live, "#hero-card time[datetime='2030-01-01T14:05:00Z']", "14:05")
      assert has_element?(live, "#hero-card #hero-flaps[data-seconds='90']")
      assert has_element?(live, "#hero-count", "1 waiting in the lobby")

      assert has_element?(
               live,
               "#hero-card a.rg-btn[href='/game/#{next.id}/lobby']",
               "Enter the lobby"
             )

      refute has_element?(live, "#hero-card.is-live")
    end

    test "shows a scheduled riddle's drop time with no lobby button", %{conn: conn} do
      next = upcoming_fixture("scheduled", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card .rg-hero__label", "#{next.category.name} · drops at")
      assert has_element?(live, "#hero-card #hero-flaps")
      assert has_element?(live, "#hero-count", "0 waiting in the lobby")
      refute has_element?(live, "#hero-card .rg-btn")
    end
  end

  describe "coming up" do
    test "says nothing else is scheduled when there is no upcoming riddle", %{conn: conn} do
      upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#schedule h2", "Coming up")
      assert has_element?(live, "#schedule", "Nothing else scheduled yet.")
      refute has_element?(live, "#schedule .rg-sched")
    end

    test "lists the riddles after the next one, soonest first, with no text", %{conn: conn} do
      upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])
      later = upcoming_fixture("scheduled", ~U[2030-01-01 16:00:00Z])
      sooner = upcoming_fixture("ready", ~U[2030-01-01 15:00:00Z])
      Ecto.Changeset.change(sooner, solve_time: 90) |> Riddlr.Repo.update!()
      draft = upcoming_fixture("scheduled", ~U[2030-01-01 15:30:00Z])
      Ecto.Changeset.change(draft, publish_status: "draft") |> Riddlr.Repo.update!()

      {:ok, live, html} = live(conn, ~p"/")

      first = "#schedule li.rg-sched:nth-child(1)"
      assert has_element?(live, "#{first} time[datetime='2030-01-01T15:00:00Z']", "15:00")
      assert has_element?(live, "#{first} .rg-sched__cat", sooner.category.name)
      assert has_element?(live, "#{first} .rg-sched__sub", "Riddle hidden until it drops")
      assert has_element?(live, "#{first} .rg-sched__solve .rg-icon")
      assert has_element?(live, "#{first} .rg-sched__solve", "01:30")

      second = "#schedule li.rg-sched:nth-child(2)"
      assert has_element?(live, "#{second} time[datetime='2030-01-01T16:00:00Z']")
      assert has_element?(live, "#{second} .rg-sched__solve", "01:00")

      refute has_element?(live, "#schedule li.rg-sched:nth-child(3)")
      refute has_element?(live, "#schedule", "Nothing else scheduled yet.")
      refute html =~ later.description
    end
  end

  describe "last riddle" do
    test "says no riddle has been solved when none has finished", %{conn: conn} do
      upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last h2", "Last riddle")
      assert has_element?(live, "#last .rg-last__empty-t", "No riddles solved yet.")

      assert has_element?(
               live,
               "#last .rg-last__empty-s",
               "Answers and winners show here once the first riddle closes."
             )

      refute has_element?(live, "#last .rg-lastcard")
    end

    test "shows the last finished riddle, its answer and first solver", %{conn: conn} do
      user = user_fixture()
      last = upcoming_fixture("completed", ~U[2030-01-01 14:05:00Z])
      GamesFixtures.solve_fixture(last, user, %{solve_time_ms: 12_340})

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last .rg-lastcard__q", "“#{last.description}”")
      assert has_element?(live, "#last .rg-lastcard__answer", "keyboard")
      assert has_element?(live, "#last .rg-lastcard__win", "Cracked first by")
      assert has_element?(live, "#last .rg-lastcard__win b", user.username)
      assert has_element?(live, "#last .rg-lastcard__win", "in 12.34s")

      assert has_element?(
               live,
               "#last a[href='/game/#{last.id}/results']",
               "See the board and chat"
             )

      refute has_element?(live, "#last .rg-last__empty")
    end

    test "names a deleted first solver as Player", %{conn: conn} do
      last = upcoming_fixture("archived", ~U[2030-01-01 14:05:00Z])

      Riddlr.Repo.insert!(%Riddlr.Gameplay.Solve{
        riddle_id: last.id,
        placement: 1,
        points: 10,
        solve_time_ms: 5_000
      })

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last .rg-lastcard__win b", "Player")
      assert has_element?(live, "#last .rg-lastcard__win", "in 5.00s")
    end

    test "says nobody cracked an archived riddle with no solver", %{conn: conn} do
      last = upcoming_fixture("archived", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last .rg-lastcard__win", "Nobody cracked it")
      assert has_element?(live, "#last a[href='/game/#{last.id}/results']")
    end

    test "shows no text or answer of a riddle that has not finished", %{conn: conn} do
      next = upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])
      upcoming_fixture("scheduled", ~U[2030-01-01 15:05:00Z])

      {:ok, _live, html} = live(conn, ~p"/")

      refute html =~ next.description
      refute html =~ "keyboard"
    end
  end

  describe "live updates" do
    test "flips the card to live when the riddle goes live", %{conn: conn} do
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      refute has_element?(live, "#hero-card.is-live")

      {:ok, _} = Games.transition(next.id, :live)

      assert has_element?(live, "#hero-card.is-live")
      assert has_element?(live, "#hero-card a.rg-btn[href='/game/#{next.id}/play']", "Jump in")
    end

    test "counts players as they join the lobby", %{conn: conn} do
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#hero-count", "0 waiting in the lobby")

      Phoenix.PubSub.subscribe(Riddlr.PubSub, Presence.lobby_topic(next.id))
      track_player(next, 7, "ada")
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}

      assert has_element?(live, "#hero-count", "1 waiting in the lobby")
    end

    test "syncs the clock to the next riddle on each tick", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 14:04:00.000000Z])
      upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")

      Frozen.advance(18, :second)
      send(live.pid, {:countdown_tick, :lobby, 42})

      assert_push_event(live, "countdown-tick", %{seconds: 42})
    end

    test "holds the clock at zero while a ready riddle waits to go live", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 14:04:59.000000Z])
      upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")

      Frozen.advance(2, :second)
      send(live.pid, {:countdown_tick, :play, 59})

      assert_push_event(live, "countdown-tick", %{seconds: 0})
    end

    # Ticks carry no riddle id, so one from the last next riddle's clock can
    # land after the switch. It must not show that riddle's time.
    test "a tick from another riddle's clock shows the next riddle's time", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 13:00:00.000000Z])
      upcoming_fixture("scheduled", ~U[2030-01-01 14:00:00Z])
      {:ok, live, _html} = live(conn, ~p"/")

      send(live.pid, {:countdown_tick, :lobby, 5})

      assert_push_event(live, "countdown-tick", %{seconds: 3600})
    end

    test "counts down the time left and counts new solves", %{conn: conn} do
      live_date = ~U[2030-01-01 14:05:00Z]
      Frozen.freeze(DateTime.add(live_date, 10, :second))
      next = upcoming_fixture("live", live_date)
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#hero-card .rg-hero__teaser", "0 solved so far.")

      Frozen.advance(20, :second)
      send(live.pid, {:countdown_tick, :play, 30})
      assert has_element?(live, "#hero-left", "0:30")

      {:correct, 1, _} = Gameplay.submit_answer(next, user_fixture(), "keyboard")
      assert has_element?(live, "#hero-card .rg-hero__teaser", "1 solved so far.")
    end

    test "moves the clock when the riddle is rescheduled", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 13:00:00.000000Z])
      next = GamesFixtures.scheduled_riddle_fixture(%{live_date: ~U[2030-01-01 14:00:00Z]})
      {:ok, live, _html} = live(conn, ~p"/")

      {:ok, _} = Games.save_riddle(next, %{"live_date" => ~U[2030-01-01 13:01:00Z]})

      assert_push_event(live, "countdown-tick", %{seconds: 60})
      assert has_element?(live, "#hero-card time[datetime='2030-01-01T13:01:00Z']")
    end

    test "drops a riddle from the card when it completes", %{conn: conn} do
      next = upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#hero-card.is-live")

      {:ok, _} = Games.transition(next.id, :completed)

      assert has_element?(live, "#hero-card", "No riddle on the schedule yet.")
      refute has_element?(live, "#hero-card.is-live")
    end

    test "shows a riddle once it is scheduled", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#hero-card", "No riddle on the schedule yet.")

      next = GamesFixtures.scheduled_riddle_fixture()

      assert has_element?(live, "#hero-card .rg-hero__label", "#{next.category.name} · drops at")
    end

    test "adds a riddle to Coming up once it is scheduled", %{conn: conn} do
      upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#schedule", "Nothing else scheduled yet.")

      later = GamesFixtures.scheduled_riddle_fixture(%{live_date: ~U[2030-01-01 15:00:00Z]})

      assert has_element?(live, "#sched-#{later.id} time[datetime='2030-01-01T15:00:00Z']")
    end

    test "fills the last riddle card when a riddle completes", %{conn: conn} do
      next = upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#last .rg-last__empty")

      {:ok, _} = Games.transition(next.id, :completed)

      assert has_element?(live, "#last .rg-lastcard__q", next.description)
      assert has_element?(live, "#last .rg-lastcard__win", "Nobody cracked it")
    end

    test "updates the last riddle card when an admin edits it", %{conn: conn} do
      last = upcoming_fixture("archived", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")

      {:ok, _} = Games.save_riddle(last, %{"answers" => ["piano"]})

      assert has_element?(live, "#last .rg-lastcard__answer", "piano")
    end
  end

  test "loads the game stylesheet and fonts", %{conn: conn} do
    response = conn |> get(~p"/") |> html_response(200)

    assert response =~ ~s(href="/assets/css/game.css")
    assert response =~ "family=Fraunces"
    assert response =~ "family=Jost"
    assert response =~ "family=Familjen+Grotesk"
  end

  describe "topbar" do
    test "renders the game shell with a brand link home", %{conn: conn} do
      doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

      refute LazyHTML.query(doc, ".rg-app .rg-topbar") |> Enum.empty?()
      refute LazyHTML.query(doc, ~s(a#topbar-brand[href="/"])) |> Enum.empty?()
      assert LazyHTML.query(doc, ".rg-header") |> Enum.empty?()
    end

    test "offers a log in link when logged out", %{conn: conn} do
      doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

      login = LazyHTML.query(doc, ~s(a#topbar-log-in[href="/users/log-in"]))
      assert LazyHTML.text(login) =~ "Log in"
      assert LazyHTML.query(doc, "#topbar-me-chip") |> Enum.empty?()
      refute LazyHTML.text(doc) =~ "Log out"
    end

    test "shows a name chip and a log out link when logged in", %{conn: conn} do
      user = user_fixture()

      doc =
        conn
        |> log_in_user(user)
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()

      chip = LazyHTML.query(doc, ~s(a#topbar-me-chip[href="/users/settings"]))
      assert LazyHTML.text(chip) =~ user.username

      tile = LazyHTML.query(chip, ".rg-tile")
      assert LazyHTML.attribute(tile, "data-tone") == ["hi"]
      assert LazyHTML.text(tile) == RiddlrWeb.GameComponents.initial(user.username)

      logout =
        LazyHTML.query(doc, ~s(a#topbar-log-out[href="/users/log-out"][data-method="delete"]))

      assert LazyHTML.text(logout) =~ "Log out"
      refute LazyHTML.text(doc) =~ "Log in"
    end
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

  # Tracks a fake player in a riddle's lobby from its own process, the way the
  # Lobby does. Returns the pid; kill it to make the player leave.
  defp track_player(riddle, id, username) do
    test = self()

    pid =
      spawn(fn ->
        {:ok, _ref} =
          Presence.track(self(), Presence.lobby_topic(riddle.id), to_string(id), %{
            username: username
          })

        send(test, {:tracked, self()})
        Process.sleep(:infinity)
      end)

    assert_receive {:tracked, ^pid}
    pid
  end
end
