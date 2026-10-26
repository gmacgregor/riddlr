defmodule RiddlrWeb.GameComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias RiddlrWeb.GameComponents

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
