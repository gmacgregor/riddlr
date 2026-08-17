defmodule RiddlrWeb.UserProfileLiveTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest
  import Riddlr.AccountsFixtures

  describe "Show profile" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "displays user profile when logged in", %{conn: conn, user: user} do
      {:ok, _show_live, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/profile")

      assert html =~ user.username
      assert html =~ user.email
    end

    test "renders the app header with account controls", %{conn: conn, user: user} do
      {:ok, _show_live, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/profile")

      assert html =~ "rg-header"
      assert html =~ "Log out"
    end

    test "redirects when not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/profile")
      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log-in"
    end
  end
end
