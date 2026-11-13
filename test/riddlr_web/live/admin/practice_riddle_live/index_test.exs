defmodule RiddlrWeb.Admin.PracticeRiddleLive.IndexTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Riddlr.AccountsFixtures
  alias Riddlr.Games

  import Riddlr.GamesFixtures, only: [system_scope: 0]

  setup do
    %{editor: AccountsFixtures.user_fixture(%{role: :editor})}
  end

  defp practice_fixture(attrs \\ %{}) do
    {:ok, practice} =
      attrs
      |> Enum.into(%{description: "What gets wetter the more it dries?", answer: "towel"})
      |> then(&Games.create_practice_riddle(system_scope(), &1))

    practice
  end

  test "lists practice riddles with their answers", %{conn: conn, editor: editor} do
    practice = practice_fixture()

    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    assert has_element?(live, "#practice_riddles-#{practice.id}", practice.description)
    assert has_element?(live, "#practice_riddles-#{practice.id}", practice.answer)
  end

  # A moderator is an admin, just not one who edits riddles.
  test "turns a moderator away", %{conn: conn} do
    user = AccountsFixtures.user_fixture(%{role: :moderator})

    assert {:error, {:redirect, %{to: "/"}}} =
             conn |> log_in_user(user) |> live(~p"/admin/practice-riddles")
  end

  for role <- [:viewer, :player] do
    test "answers 404 to a #{role}", %{conn: conn} do
      conn = log_in_user(conn, AccountsFixtures.user_fixture(%{role: unquote(role)}))

      assert_raise RiddlrWeb.NotFoundError, fn -> live(conn, ~p"/admin/practice-riddles") end
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

  test "restores the list's page heading when an edit is cancelled",
       %{conn: conn, editor: editor} do
    practice = practice_fixture()
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")
    list_heading = live |> element("header.rg-pagehead h1") |> render()

    live |> element("a[href='/admin/practice-riddles/#{practice.id}/edit']") |> render_click()
    refute live |> element("header.rg-pagehead h1") |> render() == list_heading

    live |> element("#practice-riddle-form a[href='/admin/practice-riddles']") |> render_click()
    assert_patch(live, ~p"/admin/practice-riddles")
    assert live |> element("header.rg-pagehead h1") |> render() == list_heading
  end

  test "creates a practice riddle", %{conn: conn, editor: editor} do
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    live |> element("a[href='/admin/practice-riddles/new']") |> render_click()
    assert_patch(live, ~p"/admin/practice-riddles/new")

    live
    |> form("#practice-riddle-form",
      practice_riddle: %{description: "What has hands but can't clap?", answer: "clock"}
    )
    |> render_submit()

    assert_patch(live, ~p"/admin/practice-riddles")
    assert has_element?(live, "#flash-info")
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
    assert has_element?(live, "#flash-info")
    assert has_element?(live, "#practice_riddles-#{practice.id}", "towel")
  end

  test "deletes a practice riddle", %{conn: conn, editor: editor} do
    practice = practice_fixture()
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")

    live |> element("#practice_riddles-#{practice.id} a[data-confirm]") |> render_click()

    refute has_element?(live, "#practice_riddles-#{practice.id}")
    assert has_element?(live, "#flash-info")
    assert Games.list_practice_riddles() == []
  end

  describe "role taken away mid-session" do
    setup %{conn: conn, editor: editor} do
      practice = practice_fixture()
      {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles")
      %{practice: practice, live: live}
    end

    test "refuses a delete", %{editor: editor, practice: practice, live: live} do
      demote!(editor)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live
               |> element("#practice_riddles-#{practice.id} a[data-confirm]")
               |> render_click()

      assert [_kept] = Games.list_practice_riddles()
    end

    test "refuses a save", %{editor: editor, practice: practice, live: live} do
      live |> element("a[href='/admin/practice-riddles/#{practice.id}/edit']") |> render_click()
      demote!(editor)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live
               |> form("#practice-riddle-form", practice_riddle: %{answer: "taken"})
               |> render_submit()

      assert Games.get_practice_riddle!(practice.id).answer == practice.answer
    end

    test "refuses to open the edit form", %{editor: editor, practice: practice, live: live} do
      demote!(editor)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               render_patch(live, ~p"/admin/practice-riddles/#{practice.id}/edit")
    end
  end

  defp demote!(user), do: user |> Ecto.Changeset.change(role: :viewer) |> Riddlr.Repo.update!()

  test "shows errors for a blank description and a long answer", %{conn: conn, editor: editor} do
    {:ok, live, _html} = conn |> log_in_user(editor) |> live(~p"/admin/practice-riddles/new")

    live
    |> form("#practice-riddle-form",
      practice_riddle: %{description: "", answer: String.duplicate("a", 21)}
    )
    |> render_change()

    assert has_element?(
             live,
             "#practice-riddle-form [name='practice_riddle[description]'][aria-invalid]"
           )

    assert has_element?(
             live,
             "#practice-riddle-form [name='practice_riddle[answer]'][aria-invalid]"
           )

    live
    |> form("#practice-riddle-form",
      practice_riddle: %{description: "", answer: String.duplicate("a", 21)}
    )
    |> render_submit()

    assert Games.list_practice_riddles() == []
  end
end
