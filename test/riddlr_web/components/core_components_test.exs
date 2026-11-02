defmodule RiddlrWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias RiddlrWeb.CoreComponents

  describe "flash/1" do
    test "shows a plain message" do
      html = render_component(&CoreComponents.flash/1, kind: :info, flash: %{"info" => "Saved."})

      assert html =~ "Saved."
      refute html =~ "<a"
    end

    test "shows a message with a link, escaping both" do
      flash = %{"info" => %{message: "Add <b>it</b>.", link: {"Go <now>", "/profile"}}}
      doc = render_component(&CoreComponents.flash/1, kind: :info, flash: flash)
      lazy = LazyHTML.from_fragment(doc)

      assert lazy |> LazyHTML.query("a[href='/profile']") |> LazyHTML.text() == "Go <now>"
      assert doc =~ "Add &lt;b&gt;it&lt;/b&gt;."
    end
  end
end
