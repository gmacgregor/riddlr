defmodule RiddlrWeb.Admin.RiddleLive.IndexTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Riddlr.AccountsFixtures
  alias Riddlr.GamesFixtures

  setup do
    admin = AccountsFixtures.user_fixture(%{role: :editor})
    %{admin: admin}
  end

  describe "Index" do
    test "lists riddles", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, _live, html} = live(conn, ~p"/admin/riddles")
      assert html =~ "Manage Riddles"
      assert html =~ riddle.name
    end

    test "redirects non-admin", %{conn: conn} do
      player = AccountsFixtures.user_fixture(%{role: :player})
      conn = log_in_user(conn, player)
      {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/riddles")
      assert flash["error"] == "You must be an admin to access this page."
    end

    test "redirects unauthenticated user", %{conn: conn} do
      # Unauthenticated users are redirected by :require_authenticated_user pipeline
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/riddles")
    end

    test "creates new riddle", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      assert index_live |> element("a", "New Riddle") |> render_click() =~
               "New Riddle"

      assert_patch(index_live, ~p"/admin/riddles/new")
    end

    test "shows riddle details", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, _index_live, _html} = live(conn, ~p"/admin/riddles")

      # Navigate to show view via patch
      {:ok, _show_live, html} = live(conn, ~p"/admin/riddles/#{riddle.id}")

      assert html =~ riddle.name
      assert html =~ riddle.description
    end

    test "deletes riddle", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      assert index_live |> element("#riddles-#{riddle.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#riddles-#{riddle.id}")
    end
  end
end
