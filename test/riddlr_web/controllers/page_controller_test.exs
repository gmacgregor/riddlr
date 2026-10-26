defmodule RiddlrWeb.PageControllerTest do
  use RiddlrWeb.ConnCase

  import Riddlr.AccountsFixtures

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Homepage!"
  end

  test "loads the game stylesheet and fonts", %{conn: conn} do
    response = conn |> get(~p"/") |> html_response(200)

    assert response =~ ~s(href="/assets/css/game.css")
    assert response =~ "family=Fraunces"
    assert response =~ "family=Jost"
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
      assert LazyHTML.text(login) =~ "Log in"
      assert LazyHTML.query(doc, "#topbar-me-chip") |> Enum.empty?()
      refute LazyHTML.text(doc) =~ "Log out"
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
      assert LazyHTML.attribute(tile, "data-tone") == ["hi"]
      assert LazyHTML.text(tile) == RiddlrWeb.GameComponents.initial(user.username)

      logout =
        LazyHTML.query(doc, ~s(a#topbar-log-out[href="/users/log-out"][data-method="delete"]))

      assert LazyHTML.text(logout) =~ "Log out"
      refute LazyHTML.text(doc) =~ "Log in"
    end
  end
end
