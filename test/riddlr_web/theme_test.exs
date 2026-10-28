defmodule RiddlrWeb.ThemeTest do
  use RiddlrWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures

  defp html_theme(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("html")
    |> LazyHTML.attribute("data-theme")
  end

  describe "data-theme on <html>" do
    test "is dark with no theme cookie", %{conn: conn} do
      assert html_theme(conn, ~p"/") == ["dark"]
    end

    test "follows the theme cookie", %{conn: conn} do
      for theme <- ~w(dark dusk light) do
        assert conn |> put_req_cookie("theme", theme) |> html_theme(~p"/") == [theme]
      end
    end

    test "falls back to dark for an unknown theme", %{conn: conn} do
      assert conn |> put_req_cookie("theme", "neon") |> html_theme(~p"/") == ["dark"]
    end

    test "follows the cookie on an account screen", %{conn: conn} do
      assert conn |> put_req_cookie("theme", "light") |> html_theme(~p"/users/log-in") ==
               ["light"]
    end
  end

  describe "topbar colour mode switch" do
    test "is one button naming the mode and the next one, dark by default", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(
               live,
               ~s(button#theme-switch[type=button][aria-label="Colour mode: Dark. Switch to Dusk"])
             )

      # One icon per mode; CSS shows the one that matches <html data-theme>.
      for theme <- ~w(dark dusk light) do
        assert has_element?(live, "#theme-switch svg.rg-theme__icon--#{theme}")
      end
    end

    test "names the mode from the cookie for a logged-in player", %{conn: conn} do
      {:ok, live, _html} =
        conn
        |> log_in_user(user_fixture())
        |> put_req_cookie("theme", "dusk")
        |> live(~p"/")

      assert has_element?(
               live,
               ~s(#theme-switch[aria-label="Colour mode: Dusk. Switch to Light"])
             )
    end

    test "shows on an account screen, wrapping from light to dark", %{conn: conn} do
      doc =
        conn
        |> put_req_cookie("theme", "light")
        |> get(~p"/users/log-in")
        |> html_response(200)
        |> LazyHTML.from_document()

      switch = LazyHTML.query(doc, "#theme-switch")
      assert LazyHTML.attribute(switch, "aria-label") == ["Colour mode: Light. Switch to Dark"]
    end

    test "shows on an admin page, with the theme on <html>", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture(%{role: :editor}))
        |> put_req_cookie("theme", "dusk")

      assert html_theme(conn, ~p"/admin/riddles") == ["dusk"]

      {:ok, live, _html} = live(conn, ~p"/admin/riddles")

      assert has_element?(
               live,
               ~s(#theme-switch[aria-label="Colour mode: Dusk. Switch to Light"])
             )
    end
  end
end
