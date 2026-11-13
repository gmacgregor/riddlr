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
    test "lists drafts on the draft tab", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles?status=draft")
      assert has_element?(live, "header.rg-pagehead h1")
      assert has_element?(live, "#riddles-#{riddle.id}", riddle.name)
    end

    test "lists published riddles by default, not drafts", %{conn: conn, admin: admin} do
      published = GamesFixtures.riddle_fixture(%{publish_status: "published"})
      draft = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)

      {:ok, live, _html} = live(conn, ~p"/admin/riddles")

      assert has_element?(live, "#riddles-#{published.id}")
      refute has_element?(live, "#riddles-#{draft.id}")
      assert has_element?(live, ~s(#riddles-tab-published[aria-current="page"]))
    end

    test "switches to the draft tab", %{conn: conn, admin: admin} do
      draft = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles")

      live |> element("#riddles-tab-draft") |> render_click()

      assert_patch(live, ~p"/admin/riddles?status=draft")
      assert has_element?(live, "#riddles-#{draft.id}")
      assert has_element?(live, ~s(#riddles-tab-draft[aria-current="page"]))
    end

    test "moves a riddle off the draft tab once it is published", %{conn: conn, admin: admin} do
      draft = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles?status=draft")
      assert has_element?(live, "#riddles-#{draft.id}")

      {:ok, _} =
        Riddlr.Games.save_riddle(GamesFixtures.system_scope(), draft, %{
          "publish_status" => "published"
        })

      refute has_element?(live, "#riddles-#{draft.id}")
    end

    test "shows a riddle count on each tab", %{conn: conn, admin: admin} do
      GamesFixtures.riddle_fixture()
      GamesFixtures.riddle_fixture(%{publish_status: "published"})
      counts = Riddlr.Games.count_riddles_by_status()
      conn = log_in_user(conn, admin)

      {:ok, live, _html} = live(conn, ~p"/admin/riddles")

      assert has_element?(live, "#riddles-tab-published-count", "(#{counts["published"]})")
      assert has_element?(live, "#riddles-tab-draft-count", "(#{counts["draft"]})")
    end

    test "updates tab counts when a riddle is published", %{conn: conn, admin: admin} do
      draft = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles?status=draft")

      {:ok, _} =
        Riddlr.Games.save_riddle(GamesFixtures.system_scope(), draft, %{
          "publish_status" => "published"
        })

      counts = Riddlr.Games.count_riddles_by_status()
      assert has_element?(live, "#riddles-tab-published-count", "(#{counts["published"]})")
      assert has_element?(live, "#riddles-tab-draft-count", "(#{Map.get(counts, "draft", 0)})")
    end

    test "updates tab counts when a riddle is deleted", %{conn: conn, admin: admin} do
      draft = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles?status=draft")

      live |> element("#riddles-#{draft.id} a[data-confirm]") |> render_click()

      draft_count = Map.get(Riddlr.Games.count_riddles_by_status(), "draft", 0)
      assert has_element?(live, "#riddles-tab-draft-count", "(#{draft_count})")
    end

    test "keeps the tab when the form closes", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles?status=draft")

      live |> element("a[href='/admin/riddles/new']") |> render_click()

      assert has_element?(live, ~s(#riddle-form))
      assert has_element?(live, ~s(a[href="/admin/riddles?status=draft"]))
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

    test "marks Riddles as the current nav item on riddle pages", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles/#{riddle.id}/edit")

      assert has_element?(live, ~s(.adm-nav a[aria-current="page"][href="/admin/riddles"]))
      refute has_element?(live, ~s(.adm-nav a[aria-current="page"][href="/admin/categories"]))

      live |> element("a[href='/admin/riddles/new']") |> render_click()
      assert has_element?(live, ~s(.adm-nav a[aria-current="page"][href="/admin/riddles"]))
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
      assert has_element?(live, "#riddle-form button.rg-btn.rg-btn--accent")
      assert has_element?(live, "header.rg-pagehead h1")
      refute has_element?(live, ".fieldset, .input, .select, .textarea, .btn")
    end

    test "answers 404 to a non-admin", %{conn: conn} do
      player = AccountsFixtures.user_fixture(%{role: :player})
      conn = log_in_user(conn, player)

      assert_raise RiddlrWeb.NotFoundError, fn -> live(conn, ~p"/admin/riddles") end
    end

    test "redirects unauthenticated user", %{conn: conn} do
      # Unauthenticated users are redirected by :require_authenticated_user pipeline
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/riddles")
    end

    test "restores the list's page heading when an edit is cancelled",
         %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, live, _html} = live(conn, ~p"/admin/riddles?status=draft")
      list_heading = live |> element("header.rg-pagehead h1") |> render()

      live
      |> element("#riddles-#{riddle.id} a[href='/admin/riddles/#{riddle.id}/edit']")
      |> render_click()

      refute live |> element("header.rg-pagehead h1") |> render() == list_heading

      live |> element("#riddle-form a[href='/admin/riddles?status=draft']") |> render_click()
      assert_patch(live, ~p"/admin/riddles?status=draft")
      assert live |> element("header.rg-pagehead h1") |> render() == list_heading
    end

    test "creates new riddle", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      index_live |> element("a[href='/admin/riddles/new']") |> render_click()

      assert_patch(index_live, ~p"/admin/riddles/new")
      assert has_element?(index_live, "#riddle-form")
    end

    test "deletes riddle", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles?status=draft")

      assert index_live |> element("#riddles-#{riddle.id} a[data-confirm]") |> render_click()
      refute has_element?(index_live, "#riddles-#{riddle.id}")
    end

    test "refuses a delete once the editor's role is taken away", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles?status=draft")

      admin |> Ecto.Changeset.change(role: :viewer) |> Riddlr.Repo.update!()

      assert {:error, {:live_redirect, %{to: "/"}}} =
               index_live |> element("#riddles-#{riddle.id} a[data-confirm]") |> render_click()

      assert Riddlr.Games.get_riddle!(riddle.id)
    end

    test "refuses to edit a riddle once the editor's role is taken away",
         %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, edit_live, _html} = live(conn, ~p"/admin/riddles")

      admin |> Ecto.Changeset.change(role: :viewer) |> Riddlr.Repo.update!()

      assert {:error, {:live_redirect, %{to: "/"}}} =
               render_patch(edit_live, ~p"/admin/riddles/#{riddle.id}/edit")
    end
  end

  describe "index page riddle number" do
    test "shows each riddle's number in the first column", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles?status=draft")

      assert has_element?(view, "#riddles-#{riddle.id} td:first-child", to_string(riddle.number))
    end
  end

  describe "index page season" do
    test "shows each riddle's season", %{conn: conn, admin: admin} do
      season = GamesFixtures.season_fixture(%{name: "Spring Fling"})
      riddle = GamesFixtures.riddle_fixture(%{season_id: season.id})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles?status=draft")

      assert has_element?(view, "#riddles-#{riddle.id} [data-role=season]", "Spring Fling")
    end
  end

  describe "index page play_status display" do
    test "displays play status for each riddle", %{conn: conn, admin: admin} do
      riddle1 = GamesFixtures.riddle_fixture(%{name: "Test 1", play_status: "closed"})
      riddle2 = GamesFixtures.riddle_fixture(%{name: "Test 2", play_status: "live"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles?status=draft")

      assert has_element?(view, "#riddles-#{riddle1.id} .adm-badge.adm-badge--closed")
      assert has_element?(view, "#riddles-#{riddle2.id} .adm-badge.adm-badge--live")
    end

    test "shows badge styling for different statuses", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture(%{play_status: "live"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles?status=draft")

      assert has_element?(view, "#riddles-#{riddle.id} .adm-badge.adm-badge--live")
    end
  end

  describe "status" do
    test "a ban logs an editor out of the admin pages", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)

      {:ok, _} = Riddlr.Accounts.set_user_status(admin, :banned)

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/riddles")
      refute Riddlr.Repo.get_by(Riddlr.Accounts.UserToken, user_id: admin.id)
    end

    test "answers 404 to a suspended editor", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)

      {:ok, _} = Riddlr.Accounts.set_user_status(admin, :suspended)

      assert_raise RiddlrWeb.NotFoundError, fn -> live(conn, ~p"/admin/riddles") end
    end
  end

  # A moderator is an admin, but may not read scheduled riddles or their
  # answers.
  describe "access" do
    setup do
      riddle = GamesFixtures.riddle_fixture()

      paths = [
        ~p"/admin/riddles",
        ~p"/admin/riddles/new",
        ~p"/admin/riddles/#{riddle.id}/edit"
      ]

      %{paths: paths}
    end

    test "turns a moderator away from every riddle page", %{conn: conn, paths: paths} do
      conn = log_in_user(conn, AccountsFixtures.user_fixture(%{role: :moderator}))

      for path <- paths do
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
      end
    end

    for role <- [:viewer, :player] do
      test "answers 404 to a #{role} on every riddle page", %{conn: conn, paths: paths} do
        conn = log_in_user(conn, AccountsFixtures.user_fixture(%{role: unquote(role)}))

        for path <- paths do
          assert_raise RiddlrWeb.NotFoundError, fn -> live(conn, path) end
        end
      end
    end

    for role <- [:editor, :super_admin] do
      test "lets a #{role} into every riddle page", %{conn: conn, paths: paths} do
        conn = log_in_user(conn, AccountsFixtures.user_fixture(%{role: unquote(role)}))

        for path <- paths do
          assert {:ok, _live, _html} = live(conn, path)
        end
      end
    end
  end
end
