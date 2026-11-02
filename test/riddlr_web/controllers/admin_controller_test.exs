defmodule RiddlrWeb.AdminControllerTest do
  use RiddlrWeb.ConnCase, async: true

  import Riddlr.AccountsFixtures

  describe "GET /admin" do
    for role <- [:player, :viewer] do
      test "answers 404 to a #{role}", %{conn: conn} do
        conn = log_in_user(conn, user_fixture(%{role: unquote(role)}))

        assert_error_sent 404, fn -> get(conn, ~p"/admin") end
      end
    end

    test "sends a guest to log in with no flash, then back to /admin", %{conn: conn} do
      conn = get(conn, ~p"/admin")

      assert redirected_to(conn) == ~p"/users/log-in"
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
      assert get_session(conn, :user_return_to) == "/admin"
    end

    for role <- [:editor, :moderator, :super_admin] do
      test "sends a #{role} on to the riddles", %{conn: conn} do
        conn = conn |> log_in_user(user_fixture(%{role: unquote(role)})) |> get(~p"/admin")

        assert redirected_to(conn) == ~p"/admin/riddles"
      end
    end
  end
end
