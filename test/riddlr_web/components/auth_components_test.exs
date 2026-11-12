defmodule RiddlrWeb.AuthComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias RiddlrWeb.AuthComponents

  describe "auth_mailbox_note/1" do
    test "points to the mailbox page when the local mail adapter is on" do
      html = render_component(&AuthComponents.auth_mailbox_note/1, local?: true)

      assert html =~ ~s(class="rg-auth__note")
      assert html =~ ~s(href="/dev/mailbox")
    end

    test "renders nothing with any other adapter" do
      html = render_component(&AuthComponents.auth_mailbox_note/1, local?: false)

      refute html =~ "rg-auth__note"
    end

    test "is the only place that links to the mailbox" do
      offenders =
        "lib/**/*.{ex,heex}"
        |> Path.wildcard()
        |> Enum.reject(&(&1 == "lib/riddlr_web/components/auth_components.ex"))
        |> Enum.filter(&(File.read!(&1) =~ "/dev/mailbox"))

      assert offenders == [],
             "Use <.auth_mailbox_note /> instead of a copy of the note: #{inspect(offenders)}"
    end

    # Each account screen that sends an email shows the note.
    for template <- [
          "lib/riddlr_web/controllers/user_session_html/new.html.heex",
          "lib/riddlr_web/controllers/user_registration_html/check_email.html.heex",
          "lib/riddlr_web/controllers/profile_html/show.html.heex"
        ] do
      test "#{Path.basename(Path.dirname(template))}/#{Path.basename(template)} shows the note" do
        assert File.read!(unquote(template)) =~ "<.auth_mailbox_note"
      end
    end
  end
end
