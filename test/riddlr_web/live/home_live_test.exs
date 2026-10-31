defmodule RiddlrWeb.HomeLiveTest do
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures

  alias Riddlr.Clock.Frozen
  alias Riddlr.{Gameplay, Games, GamesFixtures}
  alias Riddlr.Gameplay.Presence
  alias RiddlrWeb.GameCopy

  describe "heading" do
    test "shows today's date and a margin note when a riddle is next", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 09:00:00Z])
      upcoming_fixture("scheduled", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "h1#home-h", GameCopy.hero_heading(:future))

      assert has_element?(
               live,
               "#hero-date time[data-format='date'][datetime='2030-01-01T09:00:00Z']"
             )

      assert has_element?(live, ".rg-hero__aside")
    end

    test "shows no date or margin note when nothing is next", %{conn: conn} do
      {:ok, live, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")

      assert has_element?(live, "h1#home-h", GameCopy.hero_heading(:none))
      refute has_element?(live, "#hero-date")
      refute has_element?(live, ".rg-hero__aside")
    end
  end

  describe "timeline" do
    test "shows a round in three rows, ending at the next riddle's solve time", %{conn: conn} do
      next = upcoming_fixture("scheduled", ~U[2030-01-01 14:05:00Z])
      Ecto.Changeset.change(next, solve_time: 90) |> Riddlr.Repo.update!()

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#timeline-reel[phx-hook]")

      for {step, n} <- Enum.with_index(GameCopy.timeline_steps("1:30"), 1) do
        row = "#timeline li:nth-child(#{n})"
        assert has_element?(live, "#{row} .rg-reel__t", step.time)
        assert has_element?(live, "#{row} .rg-reel__h", step.title)
        assert has_element?(live, "#{row} .rg-reel__s", step.text)
        assert has_element?(live, "#{row} .rg-reel__note", step.note)
      end

      assert has_element?(live, "#timeline li:nth-child(3) .rg-reel__t", "1:30")
      refute has_element?(live, "#timeline li:nth-child(4)")
    end

    test "ends at the default solve time when nothing is next", %{conn: conn} do
      {:ok, live, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")

      assert has_element?(
               live,
               "#timeline li:nth-child(3) .rg-reel__t",
               GameCopy.timeline_end_default()
             )
    end
  end

  describe "hero state" do
    test "is none with no next riddle", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-sheet[data-state='none']")
    end

    test "is future, lobby or live from the next riddle's state", %{conn: conn} do
      next = upcoming_fixture("scheduled", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#hero-sheet[data-state='future']")

      {:ok, _} = Games.transition(next.id, :ready)
      assert has_element?(live, "#hero-sheet[data-state='lobby']")

      {:ok, _} = Games.transition(next.id, :live)
      assert has_element?(live, "#hero-sheet[data-state='live']")

      {:ok, _} = Games.transition(next.id, :completed)
      assert has_element?(live, "#hero-sheet[data-state='none']")
    end
  end

  describe "hero card" do
    test "shows a heading and no clock or button when there is no next riddle", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card h2")
      assert has_element?(live, "#hero-card .rg-hero__meta")
      refute has_element?(live, "#hero-flaps")
      refute has_element?(live, "#hero-card .rg-btn")
    end

    test "stamps the card and strikes out today's date when nothing is next", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 09:00:00Z])
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card .rg-void-stamp", GameCopy.hero_none_stamp())

      assert has_element?(
               live,
               "#hero-card s.rg-none__date time[data-format='date'][datetime='2030-01-01T09:00:00Z']"
             )
    end

    test "shows a blank clock and an unknown next drop when nothing is next", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card #hero-blank-flaps .rg-flap--empty")
      refute has_element?(live, "#hero-card #hero-blank-flaps[phx-hook]")
      assert has_element?(live, "#hero-card .rg-none__tbc b", GameCopy.hero_none_tbc())
    end

    test "points to Coming up when nothing is next", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card .rg-hero__note a[href='#sched-h']")
      assert has_element?(live, "#sched-h")
    end

    test "hides the practice note when there are no practice riddles", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      refute has_element?(live, "#practice")
    end

    test "shows a practice riddle and its place in the set when nothing is next", %{conn: conn} do
      practice = practice_fixture("echo")

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#practice .rg-peek__q", practice.description)
      assert has_element?(live, "#practice .rg-peek__tag", GameCopy.practice_tag(1, 1))
    end

    test "keeps the practice riddle the page first showed once it connects", %{conn: conn} do
      riddles = Enum.map(~w(echo towel clock poof keyboard darkness), &practice_fixture/1)
      kept = Enum.at(riddles, 3)

      assert conn |> get(~p"/") |> html_response(200) =~ "data-practice-id"

      {:ok, live, _html} =
        conn
        |> put_connect_params(%{"practice_id" => to_string(kept.id)})
        |> live(~p"/")

      assert has_element?(
               live,
               "#practice[data-practice-id='#{kept.id}'] .rg-peek__q",
               kept.description
             )
    end

    test "picks a practice riddle when the page sent an unknown one", %{conn: conn} do
      practice = practice_fixture("echo")

      {:ok, live, _html} =
        conn |> put_connect_params(%{"practice_id" => "nope"}) |> live(~p"/")

      assert has_element?(live, "#practice .rg-peek__q", practice.description)
    end

    test "swaps in a different practice riddle on Another riddle", %{conn: conn} do
      echo = practice_fixture("echo")
      towel = practice_fixture("towel")

      {:ok, live, _html} = live(conn, ~p"/")

      {shown, other, other_n} =
        if has_element?(live, "#practice .rg-peek__q", echo.description),
          do: {echo, towel, 2},
          else: {towel, echo, 1}

      live |> element("#practice button", GameCopy.practice_another()) |> render_click()

      refute has_element?(live, "#practice .rg-peek__q", shown.description)
      assert has_element?(live, "#practice .rg-peek__q", other.description)
      assert has_element?(live, "#practice .rg-peek__tag", GameCopy.practice_tag(other_n, 2))
    end

    test "shows a live riddle's time left and solves, and links to Play", %{conn: conn} do
      live_date = ~U[2030-01-01 14:05:00Z]
      Frozen.freeze(DateTime.add(live_date, 10, :second))
      next = upcoming_fixture("live", live_date)
      {:correct, 1, _} = Gameplay.submit_answer(next, user_fixture(), "keyboard")

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-sheet[data-state='live']")
      assert has_element?(live, "#hero-card .rg-hero__label", next.category.name)
      assert has_element?(live, "#hero-card .rg-pill--live .rg-live-dot")
      assert has_element?(live, "#hero-left", "0:50")
      assert has_element?(live, "#hero-card .rg-hero__teaser b", "1")
      refute has_element?(live, "#hero-flaps")
      assert has_element?(live, "#hero-card a.rg-btn[href='/game/#{next.id}/play']")
    end

    test "counts down to a ready riddle and links to its lobby", %{conn: conn} do
      now = ~U[2030-01-01 14:03:30.000000Z]
      Frozen.freeze(now)
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      track_player(next, 7, "ada")

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card .rg-hero__label", next.category.name)

      assert has_element?(
               live,
               "#hero-card .rg-hero__label time[datetime='2030-01-01T14:05:00Z']"
             )

      assert has_element?(live, "#hero-card #hero-flaps[data-seconds='90']")
      assert has_element?(live, "#hero-count", GameCopy.hero_waiting(1))
      assert has_element?(live, "#hero-card a.rg-btn[href='/game/#{next.id}/lobby']")

      refute has_element?(live, "#hero-sheet[data-state='live']")
    end

    test "shows a scheduled riddle's drop time with no lobby button", %{conn: conn} do
      next = upcoming_fixture("scheduled", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#hero-card .rg-hero__label", next.category.name)
      assert has_element?(live, "#hero-card #hero-flaps")

      for part <- [".rg-hero__label", ".rg-hero__meta", ".rg-hero__note"] do
        assert has_element?(live, "#hero-card #{part} time[datetime='2030-01-01T14:05:00Z']")
      end

      refute has_element?(live, "#hero-count")
      refute has_element?(live, "#hero-card .rg-btn")
    end
  end

  describe "coming up" do
    test "shows the empty line when there is no upcoming riddle", %{conn: conn} do
      upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#schedule .rg-schedule__empty")
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
      assert has_element?(live, "#{first} .rg-sched__solve .rg-icon")
      assert has_element?(live, "#{first} .rg-sched__solve", "01:30")

      second = "#schedule li.rg-sched:nth-child(2)"
      assert has_element?(live, "#{second} time[datetime='2030-01-01T16:00:00Z']")
      assert has_element?(live, "#{second} .rg-sched__solve", "01:00")

      refute has_element?(live, "#schedule li.rg-sched:nth-child(3)")
      refute has_element?(live, "#schedule .rg-schedule__empty")
      refute html =~ later.description
    end
  end

  describe "previously" do
    test "shows the empty note when no riddle has finished", %{conn: conn} do
      upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last .rg-last__empty")
      refute has_element?(live, "#last .rg-lastcard")
    end

    test "shows the last finished riddle, its answer and first solver", %{conn: conn} do
      user = user_fixture()
      last = upcoming_fixture("completed", ~U[2030-01-01 14:05:00Z])
      GamesFixtures.solve_fixture(last, user, %{solve_time_ms: 12_340})

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last .rg-lastcard__q", "“#{last.description}”")
      assert has_element?(live, "#last .rg-lastcard__answer", "keyboard")
      assert has_element?(live, "#last .rg-lastcard__win b", user.username)
      assert has_element?(live, "#last .rg-lastcard__win", GameCopy.solve_secs(12_340))
      assert has_element?(live, "#last a[href='/game/#{last.id}/results']")

      refute has_element?(live, "#last .rg-last__empty")
    end

    test "names a deleted first solver as a gone player", %{conn: conn} do
      last = upcoming_fixture("archived", ~U[2030-01-01 14:05:00Z])

      Riddlr.Repo.insert!(%Riddlr.Gameplay.Solve{
        riddle_id: last.id,
        placement: 1,
        points: 10,
        solve_time_ms: 5_000
      })

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last .rg-lastcard__win b", GameCopy.gone_player())
      assert has_element?(live, "#last .rg-lastcard__win", GameCopy.solve_secs(5_000))
    end

    test "says nobody cracked an archived riddle with no solver", %{conn: conn} do
      last = upcoming_fixture("archived", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#last .rg-lastcard__win", GameCopy.last_unsolved())
      refute has_element?(live, "#last .rg-lastcard__win b")
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
      refute has_element?(live, "#hero-sheet[data-state='live']")

      {:ok, _} = Games.transition(next.id, :live)

      assert has_element?(live, "#hero-sheet[data-state='live']")
      assert has_element?(live, "#hero-card a.rg-btn[href='/game/#{next.id}/play']")
    end

    test "counts players as they join the lobby", %{conn: conn} do
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#hero-count", GameCopy.hero_waiting(0))

      Phoenix.PubSub.subscribe(Riddlr.PubSub, Presence.lobby_topic(next.id))
      track_player(next, 7, "ada")
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}

      assert has_element?(live, "#hero-count", GameCopy.hero_waiting(1))
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
      assert has_element?(live, "#hero-card .rg-hero__teaser b", "0")

      Frozen.advance(20, :second)
      send(live.pid, {:countdown_tick, :play, 30})
      assert has_element?(live, "#hero-left", "0:30")

      {:correct, 1, _} = Gameplay.submit_answer(next, user_fixture(), "keyboard")
      assert has_element?(live, "#hero-card .rg-hero__teaser b", "1")
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
      assert has_element?(live, "#hero-sheet[data-state='live']")

      {:ok, _} = Games.transition(next.id, :completed)

      assert has_element?(live, "#hero-sheet[data-state='none']")
    end

    test "shows a practice riddle once the card has nothing next", %{conn: conn} do
      practice = practice_fixture("echo")
      next = upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      refute has_element?(live, "#practice")

      {:ok, _} = Games.transition(next.id, :completed)

      assert has_element?(live, "#practice .rg-peek__q", practice.description)
    end

    test "shows a riddle once it is scheduled", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#hero-sheet[data-state='none']")

      next = GamesFixtures.scheduled_riddle_fixture()

      assert has_element?(live, "#hero-sheet[data-state='future']")
      assert has_element?(live, "#hero-card .rg-hero__label", next.category.name)
    end

    test "adds a riddle to Coming up once it is scheduled", %{conn: conn} do
      upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#schedule .rg-schedule__empty")

      later = GamesFixtures.scheduled_riddle_fixture(%{live_date: ~U[2030-01-01 15:00:00Z]})

      assert has_element?(live, "#sched-#{later.id} time[datetime='2030-01-01T15:00:00Z']")
    end

    test "fills the last riddle card when a riddle completes", %{conn: conn} do
      next = upcoming_fixture("live", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#last .rg-last__empty")

      {:ok, _} = Games.transition(next.id, :completed)

      assert has_element?(live, "#last .rg-lastcard__q", next.description)
      assert has_element?(live, "#last .rg-lastcard__win", GameCopy.last_unsolved())
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
    assert response =~ "family=Caveat"
    assert response =~ "family=Kalam"
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
      refute Enum.empty?(login)
      assert LazyHTML.query(doc, "#topbar-me-chip") |> Enum.empty?()
      assert LazyHTML.query(doc, "#topbar-log-out") |> Enum.empty?()
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
      assert LazyHTML.attribute(tile, "data-tone") == ["variant-1"]
      assert LazyHTML.text(tile) == RiddlrWeb.GameComponents.initial(user.username)

      logout =
        LazyHTML.query(doc, ~s(a#topbar-log-out[href="/users/log-out"][data-method="delete"]))

      refute Enum.empty?(logout)
      assert LazyHTML.query(doc, "#topbar-log-in") |> Enum.empty?()
    end
  end

  describe "status pill" do
    test "shows no pill when nothing is scheduled", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      refute has_element?(live, ".rg-topbar__mid .rg-pill")
    end

    test "shows the live pill and links to Play while a riddle is live", %{conn: conn} do
      live_date = ~U[2030-01-01 14:05:00Z]
      Frozen.freeze(DateTime.add(live_date, 10, :second))
      next = upcoming_fixture("live", live_date)

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, ".rg-topbar__mid a.rg-pill--live[href='/game/#{next.id}/play']")

      assert has_element?(live, ".rg-topbar__mid .rg-pill--live .rg-live-dot")
    end

    test "counts down to a ready riddle and links to its Lobby", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 14:03:30.000000Z])
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, ".rg-topbar__mid a.rg-pill--soon[href='/game/#{next.id}/lobby']")

      assert has_element?(live, ".rg-topbar__mid [role=timer][data-seconds='90']", "01:30")
    end

    test "counts down to a scheduled riddle with no link", %{conn: conn} do
      Frozen.freeze(~U[2030-01-01 14:03:30.000000Z])
      upcoming_fixture("scheduled", ~U[2030-01-01 14:05:00Z])

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, ".rg-topbar__mid span.rg-pill--soon")
      assert has_element?(live, ".rg-topbar__mid [role=timer]", "01:30")
      refute has_element?(live, ".rg-topbar__mid a")
    end

    test "switches from the countdown pill to the live pill when the riddle goes live", %{
      conn: conn
    } do
      next = upcoming_fixture("ready", ~U[2030-01-01 14:05:00Z])
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, ".rg-topbar__mid .rg-pill--soon")

      {:ok, _} = Games.transition(next.id, :live)

      assert has_element?(live, ".rg-topbar__mid .rg-pill--live")
      refute has_element?(live, ".rg-topbar__mid .rg-pill--soon")
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

  defp practice_fixture(answer) do
    {:ok, practice} =
      Games.create_practice_riddle(%{description: "What am I? (#{answer})", answer: answer})

    practice
  end
end
