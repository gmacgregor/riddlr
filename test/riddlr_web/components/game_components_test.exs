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
      assert GameComponents.clock_str(0) == "00:00"
      assert GameComponents.clock_str(45) == "00:45"
      assert GameComponents.clock_str(3599) == "59:59"
    end

    test "shows HH:MM:SS from one hour up" do
      assert GameComponents.clock_str(3600) == "01:00:00"
      assert GameComponents.clock_str(90_061) == "25:01:01"
    end

    test "treats negative seconds as zero" do
      assert GameComponents.clock_str(-3) == "00:00"
    end
  end

  describe "flaps/1" do
    test "renders one flap per digit as a timer" do
      html = render_component(&GameComponents.flaps/1, id: "clock", seconds: 125)

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
        html = render_component(&GameComponents.flaps/1, id: "clock", seconds: seconds)
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
      html = render_component(&GameComponents.flaps/1, id: "clock", seconds: 3600)

      assert html =~ "rg-flaps--long"
      assert length(Regex.scan(~r/class="rg-flap"/, html)) == 6
    end
  end

  describe "kicker/1" do
    test "shows the riddle number, then the category" do
      html = render_component(&GameComponents.kicker/1, number: 66, category: "Classics")

      assert html =~ ~s(class="rg-kicker")
      assert html =~ ~r{<span class="rg-kicker__num">No\. 66</span>\s*<span>Classics</span>}
    end

    test "shows only the category when the riddle has no number" do
      html = render_component(&GameComponents.kicker/1, number: nil, category: "Classics")

      assert html =~ "Classics"
      refute html =~ "rg-kicker__num"
      refute html =~ "No."
    end
  end

  describe "status_pill/1" do
    test "shows a live Play riddle's number with a dot" do
      pill = render_pill(kind: :play, number: 66)

      assert_pill(pill, ".rg-pill.rg-pill--live")
      assert_pill(pill, ".rg-pill .rg-live-dot[aria-hidden=true]")
      assert text(pill, ".rg-pill") == "No. 66 · live"
      assert text(pill, ".rg-pill__long") == "· live"
    end

    test "says Live on Play when the riddle has no number" do
      pill = render_pill(kind: :play, number: nil)

      assert_pill(pill, ".rg-pill--live .rg-live-dot")
      assert text(pill, ".rg-pill") == "Live"
      refute_pill(pill, ".rg-pill__long")
    end

    test "shows Lobby with the riddle number as the long part" do
      pill = render_pill(kind: :lobby, number: 66)

      assert_pill(pill, ".rg-pill.rg-pill--soon")
      refute_pill(pill, ".rg-live-dot")
      assert text(pill, ".rg-pill") == "Lobby · No. 66"
      assert text(pill, ".rg-pill__long") == "· No. 66"
    end

    test "shows only Lobby when the riddle has no number" do
      pill = render_pill(kind: :lobby, number: nil)

      assert text(pill, ".rg-pill--soon") == "Lobby"
      refute_pill(pill, ".rg-pill__long")
    end

    test "shows Final with the riddle number as the long part" do
      pill = render_pill(kind: :results, number: 66)

      assert_pill(pill, ".rg-pill")
      refute_pill(pill, ".rg-pill--soon, .rg-pill--live, .rg-live-dot")
      assert text(pill, ".rg-pill") == "Final · No. 66"
      assert text(pill, ".rg-pill__long") == "· No. 66"
    end

    test "shows only Final when the riddle has no number" do
      pill = render_pill(kind: :results, number: nil)

      assert text(pill, ".rg-pill") == "Final"
      refute_pill(pill, ".rg-pill__long")
    end

    test "on Home, says Live now with a dot and links to Play" do
      pill = render_pill(kind: :home_live, href: "/game/7/play")

      assert_pill(pill, "a.rg-pill.rg-pill--live[href='/game/7/play']")
      assert_pill(pill, ".rg-pill .rg-live-dot[aria-hidden=true]")
      assert text(pill, ".rg-pill") == "Live now"
    end

    test "on Home, counts down to the next riddle and links to its Lobby" do
      pill = render_pill(kind: :home_next, id: "pill-clock", seconds: 90, href: "/game/7/lobby")

      assert_pill(pill, "a.rg-pill.rg-pill--soon[href='/game/7/lobby']")
      refute_pill(pill, ".rg-live-dot")
      assert text(pill, ".rg-pill") == "Next 01:30"
      assert text(pill, ".rg-pill__long") == "Next"

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
    test "in the Lobby, is far above 30s, warn from 30s and urgent from 10s" do
      count = fn seconds -> pill_count(kind: :lobby, number: 66, seconds: seconds) end

      assert count.(31) == "far"
      assert count.(30) == "warn"
      assert count.(11) == "warn"
      assert count.(10) == "urgent"
      assert count.(0) == "urgent"
    end

    test "on Home, follows the same edges, with or without a Lobby link" do
      count = fn seconds, href ->
        pill_count(kind: :home_next, id: "pill-clock", seconds: seconds, href: href)
      end

      assert count.(31, nil) == "far"
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
end
