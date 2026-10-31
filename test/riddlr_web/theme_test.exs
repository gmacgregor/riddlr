defmodule RiddlrWeb.ThemeTest do
  use RiddlrWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures

  alias RiddlrWeb.Theme

  defp document(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
    |> LazyHTML.from_document()
  end

  defp html_theme(conn, path) do
    conn
    |> document(path)
    |> LazyHTML.query("html")
    |> LazyHTML.attribute("data-theme")
  end

  describe "modes" do
    test "are light and dark" do
      assert Theme.themes() == ~w(light dark)
    end

    test "next/1 toggles between the two" do
      assert Theme.next("light") == "dark"
      assert Theme.next("dark") == "light"
    end

    test "label/1 names each mode" do
      assert Theme.label("light") == "Light"
      assert Theme.label("dark") == "Dark"
    end

    test "theme_color/1 gives the browser bar colour for each mode" do
      assert Theme.theme_color("light") == "#f5f7fb"
      assert Theme.theme_color("dark") == "#0d1526"
    end

    test "theme_color/1 matches each mode's page ground in themes.css" do
      css = File.read!("assets/css/themes.css")

      for theme <- Theme.themes() do
        [_, block] = Regex.run(~r/\[data-theme="#{theme}"\] \{(.*?)\n\}/s, css)
        [_, surface] = Regex.run(~r/--surface: (#[0-9a-f]{6});/, block)

        assert Theme.theme_color(theme) == surface
      end
    end
  end

  describe "the plug" do
    test "assigns light and copies it to the session with no cookie", %{conn: conn} do
      conn = conn |> init_test_session(%{}) |> Theme.call([])

      assert conn.assigns.theme == "light"
      assert get_session(conn, "theme") == "light"
    end

    test "assigns a dark cookie and copies it to the session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_req_cookie("theme", "dark")
        |> Theme.call([])

      assert conn.assigns.theme == "dark"
      assert get_session(conn, "theme") == "dark"
    end

    test "falls back to light for an unknown or retired cookie", %{conn: conn} do
      for theme <- ~w(neon dusk) do
        conn =
          conn
          |> init_test_session(%{})
          |> put_req_cookie("theme", theme)
          |> Theme.call([])

        assert conn.assigns.theme == "light"
      end
    end
  end

  describe "on_mount/4" do
    test "assigns the theme from the session" do
      socket = %Phoenix.LiveView.Socket{}

      assert {:cont, %{assigns: %{theme: "dark"}}} =
               Theme.on_mount(:default, %{}, %{"theme" => "dark"}, socket)

      assert {:cont, %{assigns: %{theme: "light"}}} =
               Theme.on_mount(:default, %{}, %{}, socket)
    end
  end

  describe "data-theme on <html>" do
    test "is light with no theme cookie", %{conn: conn} do
      assert html_theme(conn, ~p"/") == ["light"]
    end

    test "follows the theme cookie", %{conn: conn} do
      for theme <- ~w(light dark) do
        assert conn |> put_req_cookie("theme", theme) |> html_theme(~p"/") == [theme]
      end
    end

    test "falls back to light for an unknown theme", %{conn: conn} do
      assert conn |> put_req_cookie("theme", "neon") |> html_theme(~p"/") == ["light"]
    end

    test "follows the cookie on an account screen", %{conn: conn} do
      assert conn |> put_req_cookie("theme", "dark") |> html_theme(~p"/users/log-in") ==
               ["dark"]
    end
  end

  describe "theme-color meta on a player page" do
    test "matches the mode", %{conn: conn} do
      for {theme, color} <- [{"light", "#f5f7fb"}, {"dark", "#0d1526"}] do
        meta =
          conn
          |> put_req_cookie("theme", theme)
          |> document(~p"/")
          |> LazyHTML.query(~s(meta[name="theme-color"]))

        assert LazyHTML.attribute(meta, "content") == [color]
      end
    end
  end

  describe "topbar colour mode switch" do
    test "is one button holding the open and shut eye, light by default", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(
               live,
               ~s(button#theme-switch[type=button][aria-label="Colour mode: Light. Switch to Dark"])
             )

      # Both drawings sit in the button; CSS shows the one that matches
      # <html data-theme>, and JS copies its label and colour.
      assert has_element?(
               live,
               ~s(#theme-switch .rg-theme__eye--light[data-theme-icon=light][data-label="Colour mode: Light. Switch to Dark"][data-color="#f5f7fb"])
             )

      assert has_element?(
               live,
               ~s(#theme-switch .rg-theme__eye--dark[data-theme-icon=dark][data-label="Colour mode: Dark. Switch to Light"][data-color="#0d1526"])
             )
    end

    test "names the mode from the cookie for a logged-in player", %{conn: conn} do
      {:ok, live, _html} =
        conn
        |> log_in_user(user_fixture())
        |> put_req_cookie("theme", "dark")
        |> live(~p"/")

      assert has_element?(
               live,
               ~s(#theme-switch[aria-label="Colour mode: Dark. Switch to Light"])
             )
    end

    test "shows on an account screen", %{conn: conn} do
      switch =
        conn
        |> put_req_cookie("theme", "dark")
        |> document(~p"/users/log-in")
        |> LazyHTML.query("#theme-switch")

      assert LazyHTML.attribute(switch, "aria-label") == ["Colour mode: Dark. Switch to Light"]
    end

    test "shows on an admin page, with the theme on <html>", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture(%{role: :editor}))
        |> put_req_cookie("theme", "dark")

      assert html_theme(conn, ~p"/admin/riddles") == ["dark"]

      {:ok, live, _html} = live(conn, ~p"/admin/riddles")

      assert has_element?(
               live,
               ~s(#theme-switch[aria-label="Colour mode: Dark. Switch to Light"])
             )

      for theme <- ~w(light dark) do
        assert has_element?(live, "#theme-switch svg.rg-theme__icon--#{theme}")
      end

      refute has_element?(live, "#theme-switch svg.rg-theme__icon--dusk")
    end
  end
end
