defmodule RiddlrWeb.AdminAuthTest do
  use RiddlrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Riddlr.AccountsFixtures

  describe "on_mount :require_admin" do
    test "redirects non-admin user", %{conn: conn} do
      user = AccountsFixtures.user_fixture(%{role: :player})
      conn = log_in_user(conn, user)
      {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/riddles")
    end

    test "allows editor access", %{conn: conn} do
      user = AccountsFixtures.user_fixture(%{role: :editor})
      conn = log_in_user(conn, user)
      assert {:ok, _view, _html} = live(conn, "/admin/riddles")
    end

    test "allows moderator access", %{conn: conn} do
      user = AccountsFixtures.user_fixture(%{role: :moderator})
      conn = log_in_user(conn, user)
      assert {:ok, _view, _html} = live(conn, "/admin/riddles")
    end

    test "allows super_admin access", %{conn: conn} do
      user = AccountsFixtures.user_fixture(%{role: :super_admin})
      conn = log_in_user(conn, user)
      assert {:ok, _view, _html} = live(conn, "/admin/riddles")
    end

    test "redirects unauthenticated user", %{conn: conn} do
      {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, "/admin/riddles")
    end
  end
end
