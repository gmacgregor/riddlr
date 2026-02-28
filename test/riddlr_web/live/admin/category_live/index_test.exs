defmodule RiddlrWeb.Admin.CategoryLive.IndexTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    admin = Riddlr.AccountsFixtures.user_fixture(%{role: :editor})
    %{admin: admin}
  end

  test "lists categories", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)
    {:ok, category} = Riddlr.Games.create_category(%{name: "test category"})
    {:ok, _live, html} = live(conn, ~p"/admin/categories")
    assert html =~ "Manage Categories"
    assert html =~ category.name
  end

  test "redirects non-admin", %{conn: conn} do
    player = Riddlr.AccountsFixtures.user_fixture(%{role: :player})
    conn = log_in_user(conn, player)
    {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/categories")
  end

  test "creates new category", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("a", "New Category") |> render_click()

    assert index_live
           |> form("#category-form", category: %{name: "New Test Category"})
           |> render_submit()

    assert_patch(index_live, ~p"/admin/categories")

    html = render(index_live)
    assert html =~ "Category created"
    assert html =~ "New Test Category"
  end

  test "updates category", %{conn: conn, admin: admin} do
    {:ok, category} = Riddlr.Games.create_category(%{name: "original name"})
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("a[href='/admin/categories/#{category.id}/edit']") |> render_click()

    assert index_live
           |> form("#category-form", category: %{name: "updated name"})
           |> render_submit()

    assert_patch(index_live, ~p"/admin/categories")

    html = render(index_live)
    assert html =~ "Category updated"
    assert html =~ "updated name"
  end

  test "deletes category", %{conn: conn, admin: admin} do
    {:ok, category} = Riddlr.Games.create_category(%{name: "to delete"})
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("#categories-#{category.id} a", "Delete") |> render_click()

    refute has_element?(index_live, "#categories-#{category.id}")
    assert render(index_live) =~ "Category deleted"
  end

  test "validates required name", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("a", "New Category") |> render_click()

    assert index_live
           |> form("#category-form", category: %{name: ""})
           |> render_change() =~ "can&#39;t be blank"
  end

  test "validates unique name", %{conn: conn, admin: admin} do
    {:ok, _existing} = Riddlr.Games.create_category(%{name: "existing"})
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("a", "New Category") |> render_click()

    assert index_live
           |> form("#category-form", category: %{name: "existing"})
           |> render_submit()

    assert render(index_live) =~ "has already been taken"
  end
end
