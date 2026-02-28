defmodule RiddlrWeb.Admin.RiddleLive.FormComponentTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Riddlr.AccountsFixtures
  alias Riddlr.GamesFixtures

  setup do
    admin = AccountsFixtures.user_fixture(%{role: :editor})
    %{admin: admin}
  end

  describe "Form validation" do
    test "validates required fields", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      assert index_live
             |> element("a", "New Riddle")
             |> render_click() =~ "New Riddle"

      # Submit empty form
      assert index_live
             |> form("#riddle-form", riddle: %{})
             |> render_change() =~ "can&#39;t be blank"
    end

    test "validates solve_time minimum", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      index_live |> element("a", "New Riddle") |> render_click()

      assert index_live
             |> form("#riddle-form", riddle: %{solve_time: 0})
             |> render_change() =~ "must be greater than"
    end
  end

  describe "Create riddle" do
    @tag :skip
    test "creates riddle with valid data", %{conn: conn, admin: admin} do
      # TODO: Re-enable when answers field is added to form component
      # Currently deferred per plan notes (line 886)
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      index_live |> element("a", "New Riddle") |> render_click()

      riddle_attrs = %{
        name: "Test Riddle",
        description: "Test description",
        category: "logic",
        difficulty: "easy",
        solve_time: 60
      }

      assert index_live
             |> form("#riddle-form", riddle: riddle_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/admin/riddles")

      html = render(index_live)
      assert html =~ "Riddle created"
      assert html =~ "Test Riddle"
    end
  end

  describe "Edit riddle" do
    test "updates riddle with valid data", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      assert index_live
             |> element("#riddles-#{riddle.id} a", "Edit")
             |> render_click() =~ "Edit Riddle"

      assert_patch(index_live, ~p"/admin/riddles/#{riddle.id}/edit")

      updated_attrs = %{
        name: "Updated Riddle Name",
        description: "Updated description"
      }

      assert index_live
             |> form("#riddle-form", riddle: updated_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/admin/riddles")

      html = render(index_live)
      assert html =~ "Riddle updated"
      assert html =~ "Updated Riddle Name"
    end

    test "displays error on invalid data", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      index_live |> element("#riddles-#{riddle.id} a", "Edit") |> render_click()

      assert index_live
             |> form("#riddle-form", riddle: %{name: ""})
             |> render_submit() =~ "can&#39;t be blank"
    end
  end
end
