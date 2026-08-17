defmodule RiddlrWeb.PageControllerTest do
  use RiddlrWeb.ConnCase

  import Riddlr.AccountsFixtures

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Homepage!"
  end

  describe "header auth menu" do
    test "offers a log in link when logged out", %{conn: conn} do
      response = conn |> get(~p"/") |> html_response(200)

      assert response =~ "rg-header"
      assert response =~ ~p"/users/log-in"
      assert response =~ "Log in"
      refute response =~ "Log out"
    end

    test "shows the username and a log out link when logged in", %{conn: conn} do
      user = user_fixture()

      response =
        conn
        |> log_in_user(user)
        |> get(~p"/")
        |> html_response(200)

      assert response =~ user.username
      assert response =~ ~p"/users/settings"
      assert response =~ "Log out"
      refute response =~ "Log in"
    end
  end
end
