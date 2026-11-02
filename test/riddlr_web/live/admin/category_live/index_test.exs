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
    {:ok, live, _html} = live(conn, ~p"/admin/categories")
    assert has_element?(live, "header.rg-pagehead h1")
    assert has_element?(live, "#categories", category.name)
  end

  test "marks Categories as the current nav item", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)
    {:ok, live, _html} = live(conn, ~p"/admin/categories")

    assert has_element?(live, ~s(.adm-nav a[aria-current="page"][href="/admin/categories"]))
    refute has_element?(live, ~s(.adm-nav a[aria-current="page"][href="/admin/riddles"]))
  end

  test "answers 404 to a non-admin", %{conn: conn} do
    player = Riddlr.AccountsFixtures.user_fixture(%{role: :player})
    conn = log_in_user(conn, player)

    assert_raise RiddlrWeb.NotFoundError, fn -> live(conn, ~p"/admin/categories") end
  end

  test "creates new category", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("a[href='/admin/categories/new']") |> render_click()

    assert index_live
           |> form("#category-form", category: %{name: "New Test Category"})
           |> render_submit()

    assert_patch(index_live, ~p"/admin/categories")

    assert has_element?(index_live, "#flash-info")
    assert has_element?(index_live, "#categories", "New Test Category")
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

    assert has_element?(index_live, "#flash-info")
    assert has_element?(index_live, "#categories-#{category.id}", "updated name")
  end

  test "deletes category", %{conn: conn, admin: admin} do
    {:ok, category} = Riddlr.Games.create_category(%{name: "to delete"})
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("#categories-#{category.id} a[data-confirm]") |> render_click()

    refute has_element?(index_live, "#categories-#{category.id}")
    assert has_element?(index_live, "#flash-info")
  end

  test "validates required name", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("a[href='/admin/categories/new']") |> render_click()

    index_live
    |> form("#category-form", category: %{name: ""})
    |> render_change()

    assert has_element?(index_live, "#category-form [name='category[name]'][aria-invalid]")
    assert has_element?(index_live, "#category-form .rg-field__error")
  end

  test "validates unique name", %{conn: conn, admin: admin} do
    {:ok, _existing} = Riddlr.Games.create_category(%{name: "existing"})
    conn = log_in_user(conn, admin)
    {:ok, index_live, _html} = live(conn, ~p"/admin/categories")

    index_live |> element("a[href='/admin/categories/new']") |> render_click()

    assert index_live
           |> form("#category-form", category: %{name: "existing"})
           |> render_submit()

    assert has_element?(index_live, "#category-form [name='category[name]'][aria-invalid]")
    assert has_element?(index_live, "#category-form .rg-field__error")
  end

  # A moderator is an admin, just not one who edits categories.
  describe "access" do
    setup do
      {:ok, category} = Riddlr.Games.create_category(%{name: "access category"})

      paths = [
        ~p"/admin/categories",
        ~p"/admin/categories/new",
        ~p"/admin/categories/#{category.id}/edit"
      ]

      %{paths: paths}
    end

    test "turns a moderator away from every category page", %{conn: conn, paths: paths} do
      conn = log_in_user(conn, Riddlr.AccountsFixtures.user_fixture(%{role: :moderator}))

      for path <- paths do
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
      end
    end

    for role <- [:viewer, :player] do
      test "answers 404 to a #{role} on every category page", %{conn: conn, paths: paths} do
        conn = log_in_user(conn, Riddlr.AccountsFixtures.user_fixture(%{role: unquote(role)}))

        for path <- paths do
          assert_raise RiddlrWeb.NotFoundError, fn -> live(conn, path) end
        end
      end
    end

    for role <- [:editor, :super_admin] do
      test "lets a #{role} into every category page", %{conn: conn, paths: paths} do
        conn = log_in_user(conn, Riddlr.AccountsFixtures.user_fixture(%{role: unquote(role)}))

        for path <- paths do
          assert {:ok, _live, _html} = live(conn, path)
        end
      end
    end
  end
end
