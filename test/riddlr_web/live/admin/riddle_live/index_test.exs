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

    test "shows account controls in the admin header", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _live, html} = live(conn, ~p"/admin/riddles")

      doc = LazyHTML.from_fragment(html)

      refute LazyHTML.query(doc, ".rg-topbar a#topbar-brand .rg-brand__mark") |> Enum.empty?()
      refute LazyHTML.query(doc, ".rg-topbar a#topbar-log-out") |> Enum.empty?()
      assert html =~ admin.username
      refute html =~ "rg-auth-menu"
    end

    test "renders the riddle table and form with design system classes, not daisyUI",
         %{conn: conn, admin: admin} do
      GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)

      {:ok, live, _html} = live(conn, ~p"/admin/riddles")
      assert has_element?(live, "table.rg-table")
      refute has_element?(live, ".table, .table-zebra")

      {:ok, live, _html} = live(conn, ~p"/admin/riddles/new")
      assert has_element?(live, "#riddle-form .rg-field input.rg-input")
      assert has_element?(live, "#riddle-form .rg-field select.rg-input")
      assert has_element?(live, "#riddle-form .rg-field textarea.rg-input")
      assert has_element?(live, "#riddle-form button.rg-btn.rg-btn--hi")
      assert has_element?(live, "header.rg-pagehead h1")
      refute has_element?(live, ".fieldset, .input, .select, .textarea, .btn")
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
               "New riddle"

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

  describe "index page riddle number" do
    test "shows each riddle's number in the first column", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles")

      assert has_element?(view, "th:first-child", "No.")
      assert has_element?(view, "#riddles-#{riddle.id} td:first-child", to_string(riddle.number))
    end
  end

  describe "index page play_status display" do
    test "displays play status for each riddle", %{conn: conn, admin: admin} do
      _riddle1 = GamesFixtures.riddle_fixture(%{name: "Test 1", play_status: "closed"})
      _riddle2 = GamesFixtures.riddle_fixture(%{name: "Test 2", play_status: "live"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/riddles")

      assert html =~ "unscheduled"
      assert html =~ "live"
    end

    test "shows badge styling for different statuses", %{conn: conn, admin: admin} do
      _riddle = GamesFixtures.riddle_fixture(%{play_status: "live"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/riddles")

      # Should have badge component for status
      assert html =~ "live"
    end
  end
end
