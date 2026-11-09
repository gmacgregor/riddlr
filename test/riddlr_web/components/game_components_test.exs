defmodule RiddlrWeb.GameComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias RiddlrWeb.GameComponents
  alias RiddlrWeb.GameCopy

  describe "tone/1" do
    test "picks a tone from the sum of the name's char codes" do
      # "ab" = 97 + 98 = 195, 195 mod 6 = 3 -> variant-4
      assert GameComponents.tone("ab") == "variant-4"
      # "a" = 97, 97 mod 6 = 1 -> variant-2
      assert GameComponents.tone("a") == "variant-2"
    end

    test "gives the same tone every time for a name" do
      assert GameComponents.tone("gmac") == GameComponents.tone("gmac")
    end

    test "always gives the current user variant-1" do
      # "a" alone is variant-2; as the current user it is variant-1.
      assert GameComponents.tone("a", "a") == "variant-1"
      assert GameComponents.tone("a", "b") == "variant-2"
      assert GameComponents.tone("a", nil) == "variant-2"
    end
  end

  describe "initial/1" do
    test "takes the first letter or digit, upper-cased" do
      assert GameComponents.initial("gmac") == "G"
      assert GameComponents.initial("_x9") == "X"
    end

    test "falls back to ? when the name has no letter or digit" do
      assert GameComponents.initial("__") == "?"
    end
  end

  describe "tile/1" do
    test "renders the initial with its tone and size" do
      html = render_component(&GameComponents.tile/1, initial: "G", tone: "variant-3", size: "sm")

      assert html =~ ~s(data-tone="variant-3")
      assert html =~ "rg-tile--sm"
      assert html =~ ">G</span>"
    end

    test "defaults to variant-5 at the base size" do
      html = render_component(&GameComponents.tile/1, initial: "Q")

      assert html =~ ~s(data-tone="variant-5")
      refute html =~ "rg-tile--"
    end

    test "renders each tile tone as its data-tone" do
      for n <- 1..6 do
        tone = "variant-#{n}"
        html = render_component(&GameComponents.tile/1, initial: "G", tone: tone)
        assert html =~ ~s(data-tone="#{tone}")
      end
    end
  end

  describe "clock_str/1" do
    test "shows MM:SS under an hour" do
      assert GameComponents.Clock.clock_str(0) == "00:00"
      assert GameComponents.Clock.clock_str(45) == "00:45"
      assert GameComponents.Clock.clock_str(3599) == "59:59"
    end

    test "shows HH:MM:SS from one hour up" do
      assert GameComponents.Clock.clock_str(3600) == "01:00:00"
      assert GameComponents.Clock.clock_str(86_399) == "23:59:59"
    end

    test "shows DD:HH:MM from one day up" do
      assert GameComponents.Clock.clock_str(86_400) == "01:00:00"
      assert GameComponents.Clock.clock_str(90_061) == "01:01:01"
      assert GameComponents.Clock.clock_str(593_308) == "06:20:48"
      assert GameComponents.Clock.clock_str(12 * 86_400 + 59) == "12:00:00"
      assert GameComponents.Clock.clock_str(100 * 86_400) == "100:00:00"
    end

    test "treats negative seconds as zero" do
      assert GameComponents.Clock.clock_str(-3) == "00:00"
    end
  end

  describe "clock_groups/1" do
    test "labels the groups from one day up" do
      assert GameComponents.Clock.clock_groups(593_308) ==
               [{"06", "days"}, {"20", "hours"}, {"48", "mins"}]
    end

    test "uses the singular unit for a count of one" do
      assert GameComponents.Clock.clock_groups(90_061) ==
               [{"01", "day"}, {"01", "hour"}, {"01", "min"}]
    end

    test "leaves the groups unlabelled under a day" do
      assert GameComponents.Clock.clock_groups(86_399) ==
               [{"23", nil}, {"59", nil}, {"59", nil}]

      assert GameComponents.Clock.clock_groups(125) == [{"02", nil}, {"05", nil}]
    end
  end

  describe "clock_short/1" do
    test "reads as days, hours and minutes from one day up" do
      assert GameComponents.Clock.clock_short(593_308) == "6d 20h 48m"
      assert GameComponents.Clock.clock_short(86_400) == "1d 0h 0m"
    end

    test "reads as the clock under a day" do
      assert GameComponents.Clock.clock_short(86_399) == "23:59:59"
      assert GameComponents.Clock.clock_short(125) == "02:05"
    end
  end

  describe "clock_spoken/1" do
    test "spells out the units from one day up" do
      assert GameComponents.Clock.clock_spoken(593_308) == "6 days, 20 hours, 48 minutes"
      assert GameComponents.Clock.clock_spoken(90_061) == "1 day, 1 hour, 1 minute"
    end

    test "reads as the clock under a day" do
      assert GameComponents.Clock.clock_spoken(125) == "02:05"
    end
  end

  describe "flaps/1" do
    test "renders one flap per digit as a timer" do
      html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: 125)

      assert html =~ ~s(id="clock")
      assert html =~ ~s(role="timer")
      assert html =~ ~s(data-seconds="125")
      assert html =~ ~s(aria-label="02:05 #{GameCopy.clock_label_tail()}")
      assert html =~ ~s(data-label-tail="#{GameCopy.clock_label_tail()}")
      assert html =~ ~s(phx-update="ignore")
      assert length(Regex.scan(~r/class="rg-flap"/, html)) == 4
      assert length(Regex.scan(~r/class="rg-flaps__sep"/, html)) == 1
      refute html =~ "rg-flaps--long"
    end

    test "warns at 6 to 10 seconds and turns critical at 5 or less" do
      classes = fn seconds ->
        html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: seconds)
        [_, class] = Regex.run(~r/<div[^>]*class="([^"]*)"/, html)
        class
      end

      refute classes.(11) =~ "is-"
      assert classes.(10) =~ "is-warn"
      assert classes.(6) =~ "is-warn"
      refute classes.(6) =~ "is-crit"
      assert classes.(5) =~ "is-crit"
      refute classes.(5) =~ "is-warn"
      assert classes.(0) =~ "is-crit"
    end

    test "uses the long style from one hour up" do
      html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: 3600)

      assert html =~ "rg-flaps--long"
      assert length(Regex.scan(~r/class="rg-flap"/, html)) == 6
    end

    test "labels days, hours and minutes from one day up" do
      html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: 593_308)

      assert html =~ "rg-flaps--days"
      refute html =~ "rg-flaps--long"
      assert length(Regex.scan(~r/class="rg-flap( rg-flap--pulse)?"/, html)) == 6
      assert length(Regex.scan(~r/class="rg-flaps__sep"/, html)) == 2
      assert length(Regex.scan(~r/class="rg-flaps__group"/, html)) == 3

      assert Regex.scan(~r/class="rg-flaps__unit"[^>]*>([^<]*)</, html, capture: :all_but_first) ==
               [["days"], ["hours"], ["mins"]]

      assert html =~
               ~s(aria-label="6 days, 20 hours, 48 minutes #{GameCopy.clock_label_tail()}")
    end

    test "pulses the last minute tile from one day up" do
      html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: 593_308)

      assert [_] = Regex.scan(~r/<span class="rg-flap rg-flap--pulse"[^>]*>8</, html)
    end

    test "pulses the minute tile under the singular min label" do
      html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: 90_061)

      assert [_] = Regex.scan(~r/<span class="rg-flap rg-flap--pulse"[^>]*>1</, html)
    end

    test "pulses no tile under a day" do
      html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: 86_399)

      refute html =~ "rg-flap--pulse"
    end

    test "has no unit labels under a day" do
      html = render_component(&GameComponents.Clock.flaps/1, id: "clock", seconds: 86_399)

      refute html =~ "rg-flaps__unit"
      refute html =~ "rg-flaps--days"
    end
  end

  describe "practice_note/1" do
    @riddle %{description: "What has hands but can't clap?", answer: "Big Ben"}

    test "shows the riddle, its place in the set and a hidden answer" do
      html =
        render_component(&GameComponents.Practice.practice_note/1,
          id: "practice",
          riddle: @riddle,
          n: 2,
          total: 5
        )

      assert html =~ GameCopy.Home.practice_heading()
      assert html =~ GameCopy.Home.practice_tag(2, 5)
      assert html =~ escape(GameCopy.Home.practice_note())
      assert html =~ escape(@riddle.description)
      # One tile per letter and a gap for the space; the answer starts closed.
      assert length(Regex.scan(~r/class="rg-pk"/, html)) == 6
      assert length(Regex.scan(~r/class="rg-pk-gap"/, html)) == 1
      refute html =~ "rg-peek__a is-open"
      assert html =~ ~s(aria-expanded="false")
      assert html =~ ~s(aria-controls="practice-answer")
      assert html =~ GameCopy.Home.practice_peek()
      assert html =~ ~s(role="status")
    end

    test "puts both button texts and both status lines on the peek button for the JS toggle" do
      html =
        render_component(&GameComponents.Practice.practice_note/1,
          id: "practice",
          riddle: @riddle,
          n: 1,
          total: 1
        )

      assert html =~ GameCopy.Home.practice_hide()
      assert html =~ GameCopy.Home.practice_status_shown("Big Ben")
      assert html =~ GameCopy.Home.practice_status_hidden("Big Ben")
    end

    test "offers Another riddle only when there is another to show" do
      note = fn total ->
        render_component(&GameComponents.Practice.practice_note/1,
          id: "practice",
          riddle: @riddle,
          n: 1,
          total: total,
          on_another: "another"
        )
      end

      assert note.(2) =~ GameCopy.Home.practice_another()
      refute note.(1) =~ GameCopy.Home.practice_another()
    end

    test "counts only letters and digits in the hidden answer's status" do
      assert GameCopy.Home.practice_status_hidden("Big Ben") =~ whole_number("6")
      assert GameCopy.Home.practice_status_hidden("R2-D2!") =~ whole_number("4")
      assert GameCopy.Home.practice_status_hidden("I") =~ whole_number("1")

      # One letter reads as singular.
      one = String.replace(GameCopy.Home.practice_status_hidden("I"), "1", "N")
      six = String.replace(GameCopy.Home.practice_status_hidden("Big Ben"), "6", "N")
      refute one == six
    end

    defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  describe "drop_time/1" do
    @now ~U[2030-01-01 17:00:00Z]

    @spec drop_time(keyword()) :: String.t()
    defp drop_time(attrs) do
      render_component(&GameComponents.Clock.drop_time/1, [id: "t", now: @now] ++ attrs)
    end

    test "renders the short form in Eastern time" do
      time =
        drop_time(at: ~U[2030-07-08 17:17:00Z])
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("time")

      assert LazyHTML.attribute(time, "datetime") == ["2030-07-08T17:17:00Z"]
      assert LazyHTML.text(time) == "Jul 8, 1:17pm EDT"
    end

    test "lowercases Today and Tomorrow mid-sentence" do
      html = drop_time(at: ~U[2030-01-01 18:17:00Z], format: "long", mid_sentence: true)
      time = html |> LazyHTML.from_fragment() |> LazyHTML.query("time")

      assert LazyHTML.text(time) == "today at 1:17pm EST"
    end

    test "renders the long form with the date and time underlined, not the weekday" do
      html = drop_time(at: ~U[2030-11-04 18:17:00Z], format: "long")
      time = html |> LazyHTML.from_fragment() |> LazyHTML.query("time")

      assert LazyHTML.text(time) == "Monday, Nov 4, 1:17pm EST"
      assert LazyHTML.text(LazyHTML.query(time, ".rg-underlined")) == "Nov 4, 1:17pm EST"
      assert time |> LazyHTML.query("svg") |> Enum.empty?()
    end

    test "underlines the whole relative time in the long form" do
      html = drop_time(at: ~U[2030-01-01 18:17:00Z], format: "long")
      line = html |> LazyHTML.from_fragment() |> LazyHTML.query(".rg-underlined")

      assert LazyHTML.text(line) == "Today at 1:17pm EST"
    end

    test "adds a hidden local-time line holding the instant and display zone" do
      doc = drop_time(at: ~U[2030-07-08 17:17:00Z]) |> LazyHTML.from_fragment()
      line = LazyHTML.query(doc, "#t-local")

      assert LazyHTML.attribute(line, "hidden") == [""]
      assert LazyHTML.attribute(line, "data-at") == ["2030-07-08T17:17:00Z"]
      assert LazyHTML.attribute(line, "data-zone") == ["America/Toronto"]
      assert LazyHTML.attribute(line, "phx-hook") != []
      assert LazyHTML.text(line) =~ GameCopy.Home.drop_local_lead()
    end

    test "leaves out the local-time line when told to" do
      doc = drop_time(at: ~U[2030-07-08 17:17:00Z], local: false) |> LazyHTML.from_fragment()

      assert doc |> LazyHTML.query("#t-local") |> Enum.empty?()
    end
  end

  describe "kicker/1" do
    test "shows the riddle number, then the category" do
      html = render_component(&GameComponents.kicker/1, number: 66, category: "Classics")

      assert html =~ ~s(class="rg-kicker")
      assert html =~ ~r{<span class="rg-kicker__num">[^<]*66</span>\s*<span>Classics</span>}
    end

    test "shows the name before the category when given one" do
      html =
        render_component(&GameComponents.kicker/1,
          number: 66,
          name: "Echo",
          category: "Classics"
        )

      assert html =~
               ~r{<span class="rg-kicker__num">[^<]*66</span>\s*<span>Echo · Classics</span>}
    end

    test "shows only the category when the riddle has no number" do
      html = render_component(&GameComponents.kicker/1, number: nil, category: "Classics")

      assert html =~ "Classics"
      refute html =~ "rg-kicker__num"
    end
  end

  describe "status_pill/1" do
    test "shows a live Play riddle's number with a dot" do
      pill = render_pill(kind: :play, number: 66)

      assert_pill(pill, ".rg-pill.rg-pill--live")
      assert_pill(pill, ".rg-pill .rg-live-dot[aria-hidden=true]")
      assert text(pill, ".rg-pill") =~ "66"
      assert_pill(pill, ".rg-pill .rg-pill__long")
    end

    test "says Live on Play when the riddle has no number" do
      pill = render_pill(kind: :play, number: nil)

      assert_pill(pill, ".rg-pill--live .rg-live-dot")
      refute text(pill, ".rg-pill") == ""
      refute_pill(pill, ".rg-pill__long")
    end

    test "shows Lobby with the riddle number as the long part" do
      pill = render_pill(kind: :lobby, number: 66)

      assert_pill(pill, ".rg-pill.rg-pill--soon")
      refute_pill(pill, ".rg-live-dot")
      assert text(pill, ".rg-pill__long") =~ "66"
    end

    test "shows only Lobby when the riddle has no number" do
      pill = render_pill(kind: :lobby, number: nil)

      assert_pill(pill, ".rg-pill.rg-pill--soon")
      refute text(pill, ".rg-pill--soon") == ""
      refute_pill(pill, ".rg-pill__long")
    end

    test "shows Final with the riddle number as the long part" do
      pill = render_pill(kind: :results, number: 66)

      assert_pill(pill, ".rg-pill")
      refute_pill(pill, ".rg-pill--soon, .rg-pill--live, .rg-live-dot")
      assert text(pill, ".rg-pill__long") =~ "66"
    end

    test "shows only Final when the riddle has no number" do
      pill = render_pill(kind: :results, number: nil)

      refute text(pill, ".rg-pill") == ""
      refute_pill(pill, ".rg-pill__long")
    end

    test "on Home, says Live now with a dot and links to Play" do
      pill = render_pill(kind: :home_live, href: "/game/7/play")

      assert_pill(pill, "a.rg-pill.rg-pill--live[href='/game/7/play']")
      assert_pill(pill, ".rg-pill .rg-live-dot[aria-hidden=true]")
    end

    test "on Home, counts down to the next riddle and links to its Lobby" do
      pill = render_pill(kind: :home_next, id: "pill-clock", seconds: 90, href: "/game/7/lobby")

      assert_pill(pill, "a.rg-pill.rg-pill--soon[href='/game/7/lobby']")
      refute_pill(pill, ".rg-live-dot")
      assert text(pill, ".rg-pill") =~ "01:30"
      assert_pill(pill, ".rg-pill .rg-pill__long")

      assert_pill(
        pill,
        "#pill-clock[phx-hook][phx-update=ignore][data-seconds='90'][role=timer]"
      )

      assert text(pill, "#pill-clock") == "01:30"
    end

    test "on Home, shows the countdown with no link when the Lobby is not open" do
      pill = render_pill(kind: :home_next, id: "pill-clock", seconds: 3700)

      assert_pill(pill, "span.rg-pill.rg-pill--soon")
      refute_pill(pill, "a")
      assert text(pill, "#pill-clock") == "01:01:40"
    end
  end

  describe "status_pill/1 countdown dot" do
    test "in the Lobby, is future above 30s, warn from 30s and urgent from 10s" do
      count = fn seconds -> pill_count(kind: :lobby, number: 66, seconds: seconds) end

      assert count.(31) == "future"
      assert count.(30) == "warn"
      assert count.(11) == "warn"
      assert count.(10) == "urgent"
      assert count.(0) == "urgent"
    end

    test "on Home, follows the same edges, with or without a Lobby link" do
      count = fn seconds, href ->
        pill_count(kind: :home_next, id: "pill-clock", seconds: seconds, href: href)
      end

      assert count.(31, nil) == "future"
      assert count.(30, "/game/7/lobby") == "warn"
      assert count.(11, "/game/7/lobby") == "warn"
      assert count.(10, "/game/7/lobby") == "urgent"
    end

    test "is left off without seconds, and on the live and final pills" do
      for attrs <- [
            [kind: :lobby, number: 66],
            [kind: :play, number: 66, seconds: 5],
            [kind: :results, number: 66, seconds: 5],
            [kind: :home_live, href: "/game/7/play", seconds: 5]
          ] do
        refute_pill(render_pill(attrs), "[data-count]")
      end
    end
  end

  defp pill_count(attrs) do
    pill = render_pill(attrs)
    [count] = pill |> LazyHTML.query(".rg-pill") |> LazyHTML.attribute("data-count")
    count
  end

  defp render_pill(attrs) do
    (&GameComponents.status_pill/1) |> render_component(attrs) |> LazyHTML.from_fragment()
  end

  defp assert_pill(pill, selector) do
    assert pill |> LazyHTML.query(selector) |> Enum.count() == 1, "no #{selector}"
  end

  defp refute_pill(pill, selector) do
    assert pill |> LazyHTML.query(selector) |> Enum.empty?(), "unexpected #{selector}"
  end

  defp text(pill, selector) do
    pill
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.replace("\u00A0", " ")
    |> String.split()
    |> Enum.join(" ")
  end

  describe "room_cells/2" do
    test "pads a small room with empty cells up to 8" do
      assert GameComponents.room_cells(Enum.to_list(1..3), 4) == %{
               visible: [1, 2, 3],
               more: 0,
               pad: 5
             }
    end

    test "shows everyone when the room fits, with no padding past 8" do
      players = Enum.to_list(1..12)
      assert GameComponents.room_cells(players, 4) == %{visible: players, more: 0, pad: 0}
    end

    test "past three rows, shows cells minus two and counts the rest" do
      players = Enum.to_list(1..50)
      # 4 cols x 3 rows = 12 cells; 10 tiles + the two-cell "more" cell.
      assert GameComponents.room_cells(players, 4) ==
               %{visible: Enum.to_list(1..10), more: 40, pad: 0}
    end

    test "clamps the column count to 4..12" do
      players = Enum.to_list(1..200)
      assert %{visible: v} = GameComponents.room_cells(players, 1)
      assert length(v) == 10
      assert %{visible: v} = GameComponents.room_cells(players, 1000)
      assert length(v) == 34
    end
  end

  # Matches `n` as a whole number, so "6" does not match inside "16" or "1,600".
  @spec whole_number(String.t()) :: Regex.t()
  defp whole_number(n), do: ~r/(?<![\d,])#{Regex.escape(n)}(?![\d,])/
end
