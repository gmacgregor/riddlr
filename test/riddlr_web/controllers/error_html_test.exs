defmodule RiddlrWeb.ErrorHTMLTest do
  use RiddlrWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]
  import Riddlr.AccountsFixtures

  alias RiddlrWeb.GameCopy

  describe "404" do
    test "renders with no assigns at all, as a guest in light mode" do
      html = render_to_string(RiddlrWeb.ErrorHTML, "404", "html", [])

      assert html =~ ~s(data-theme="light")
      assert html =~ ~s(id="topbar-log-in")
      assert html =~ ~s(id="not-found")
    end

    test "answers an unknown page with the riddle and a way home", %{conn: conn} do
      {404, _headers, body} = assert_error_sent 404, fn -> get(conn, "/no/such/page") end
      doc = LazyHTML.from_document(body)

      assert text(doc, "#not-found h1.rg-lost__riddle") =~ GameCopy.Errors.not_found_riddle()
      assert text(doc, "#not-found a.rg-link-btn") =~ GameCopy.Errors.not_found_home()
      assert attr(doc, "#not-found a.rg-link-btn", "href") == "/"
      assert text(doc, "title") =~ GameCopy.Errors.not_found_title()
      assert text(doc, ".rg-topbar") =~ "Log in"
    end

    test "keeps the player's account and colour mode in the topbar", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> put_req_cookie("theme", "dark")

      {404, _headers, body} = assert_error_sent 404, fn -> get(conn, "/no/such/page") end
      doc = LazyHTML.from_document(body)

      assert attr(doc, "html", "data-theme") == "dark"
      assert text(doc, "#topbar-me-chip") =~ user.username
    end

    test "is the page a non-admin gets for an admin page", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      {404, _headers, body} = assert_error_sent 404, fn -> get(conn, "/admin/riddles") end

      assert body =~ ~s(id="not-found")
    end
  end

  describe "any other error" do
    for status <- ~w(500 400 403 405 503) do
      test "poses the crisis riddle for a #{status}" do
        html = render_to_string(RiddlrWeb.ErrorHTML, unquote(status), "html", [])

        assert html =~ ~s(id="crisis")
        assert html =~ GameCopy.Errors.crisis_riddle()
        assert html =~ GameCopy.Errors.crisis_tail()
        assert html =~ ~s(id="topbar-log-in")
      end
    end

    test "is the page a failed CSRF check gets", %{conn: conn} do
      # ConnTest skips the CSRF check unless told not to.
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> put_private(:plug_skip_csrf_protection, false)

      {403, _headers, body} =
        assert_error_sent 403, fn -> post(conn, ~p"/users/log-in", %{}) end

      doc = LazyHTML.from_document(body)
      assert text(doc, "#crisis h1.rg-lost__riddle") =~ GameCopy.Errors.crisis_riddle()
      assert attr(doc, "#crisis a.rg-link-btn", "href") == "/"
      assert text(doc, "title") =~ GameCopy.Errors.crisis_title()
    end

    test "falls back to plain text when the page itself breaks" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert render_to_string(RiddlrWeb.ErrorHTML, "500", "html", flash: :bad) ==
                   "Internal Server Error"
        end)

      assert log =~ "Error page failed to render"
    end
  end

  defp text(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.text()

  defp attr(doc, selector, name),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name) |> List.first()
end
