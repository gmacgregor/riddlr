defmodule RiddlrWeb.GameComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias RiddlrWeb.GameComponents
  alias RiddlrWeb.GameCopy

  describe "tone/1" do
    test "picks a tone from the sum of the name's char codes" do
      # "ab" = 97 + 98 = 195, 195 mod 6 = 3 -> rose
      assert GameComponents.tone("ab") == "rose"
      # "a" = 97, 97 mod 6 = 1 -> mint
      assert GameComponents.tone("a") == "mint"
    end

    test "gives the same tone every time for a name" do
      assert GameComponents.tone("gmac") == GameComponents.tone("gmac")
    end

    test "always gives the current user hi" do
      # "a" alone is mint; as the current user it is hi.
      assert GameComponents.tone("a", "a") == "hi"
      assert GameComponents.tone("a", "b") == "mint"
      assert GameComponents.tone("a", nil) == "mint"
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
      html = render_component(&GameComponents.tile/1, initial: "G", tone: "sky", size: "sm")

      assert html =~ ~s(data-tone="sky")
      assert html =~ "rg-tile--sm"
      assert html =~ ">G</span>"
    end

    test "defaults to the paper tone at the base size" do
      html = render_component(&GameComponents.tile/1, initial: "Q")

      assert html =~ ~s(data-tone="paper")
      refute html =~ "rg-tile--"
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
end
