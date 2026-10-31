defmodule RiddlrWeb.Admin.PracticeRiddleLive.IndexTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Riddlr.AccountsFixtures
  alias Riddlr.Games

  setup do
    %{editor: AccountsFixtures.user_fixture(%{role: :editor})}
  end

  defp practice_fixture(attrs \\ %{}) do
    {:ok, practice} =
      attrs
      |> Enum.into(%{description: "What gets wetter the more it dries?", answer: "towel"})
      |> Games.create_practice_riddle()

    practice
  end

  test "lists practice riddles with their answers", %{conn: conn, editor: editor} do
    practice = practice_fixture()

    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    assert has_element?(live, "#practice_riddles-#{practice.id}", practice.description)
    assert has_element?(live, "#practice_riddles-#{practice.id}", practice.answer)
  end

  for role <- [:moderator, :viewer, :player] do
    test "refuses a #{role}", %{conn: conn} do
      user = AccountsFixtures.user_fixture(%{role: unquote(role)})

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(user) |> live(~p"/admin/practice-riddles")
    end
  end

  test "lets a super admin in", %{conn: conn} do
    user = AccountsFixtures.user_fixture(%{role: :super_admin})

    assert {:ok, _live, _html} = conn |> log_in_user(user) |> live(~p"/admin/practice-riddles")
  end

  test "marks Practice riddles as the current nav item", %{conn: conn, editor: editor} do
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    assert has_element?(
             live,
             ~s(.adm-nav a[aria-current="page"][href="/admin/practice-riddles"])
           )
  end

  test "hides the nav link from a moderator", %{conn: conn} do
    moderator = AccountsFixtures.user_fixture(%{role: :moderator})

    {:ok, live, _html} = conn |> log_in_user(moderator) |> live(~p"/admin/categories")

    refute has_element?(live, ~s(.adm-nav a[href="/admin/practice-riddles"]))
  end

  test "creates a practice riddle", %{conn: conn, editor: editor} do
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    live |> element("a", "New practice riddle") |> render_click()
    assert_patch(live, ~p"/admin/practice-riddles/new")

    live
    |> form("#practice-riddle-form",
      practice_riddle: %{description: "What has hands but can't clap?", answer: "clock"}
    )
    |> render_submit()

    assert_patch(live, ~p"/admin/practice-riddles")
    assert render(live) =~ "Practice riddle created"
    assert [%{answer: "clock"}] = Games.list_practice_riddles()
    assert has_element?(live, "#practice_riddles td", "clock")
  end

  test "updates a practice riddle", %{conn: conn, editor: editor} do
    practice = practice_fixture(%{answer: "towle"})
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    live |> element("a[href='/admin/practice-riddles/#{practice.id}/edit']") |> render_click()

    live
    |> form("#practice-riddle-form", practice_riddle: %{answer: "towel"})
    |> render_submit()

    assert_patch(live, ~p"/admin/practice-riddles")
    assert render(live) =~ "Practice riddle updated"
    assert has_element?(live, "#practice_riddles-#{practice.id}", "towel")
  end

  test "deletes a practice riddle", %{conn: conn, editor: editor} do
    practice = practice_fixture()
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    live |> element("#practice_riddles-#{practice.id} a", "Delete") |> render_click()

    refute has_element?(live, "#practice_riddles-#{practice.id}")
    assert render(live) =~ "Practice riddle deleted"
    assert Games.list_practice_riddles() == []
  end

  test "shows errors for a blank description and a long answer", %{conn: conn, editor: editor} do
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles/new")

    html =
      live
      |> form("#practice-riddle-form",
        practice_riddle: %{description: "", answer: String.duplicate("a", 21)}
      )
      |> render_change()

    assert html =~ "can&#39;t be blank"
    assert html =~ "should be at most 20 character(s)"

    live
    |> form("#practice-riddle-form",
      practice_riddle: %{description: "", answer: String.duplicate("a", 21)}
    )
    |> render_submit()

    assert Games.list_practice_riddles() == []
  end
end
