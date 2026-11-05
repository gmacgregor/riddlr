defmodule RiddlrWeb.Admin.SeasonLive.IndexTest do
  use RiddlrWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Riddlr.GamesFixtures, only: [season_fixture: 1]

  setup %{conn: conn} do
    admin = Riddlr.AccountsFixtures.user_fixture(%{role: :editor})
    %{admin: admin, conn: log_in_user(conn, admin)}
  end

  test "creates a season and lists it", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/admin/seasons")

    live |> element("a[href='/admin/seasons/new']") |> render_click()

    live
    |> form("#season-form",
      season: %{
        name: "Saison d'été 2031",
        description: "Hot riddles",
        starts_on: "2031-06-01",
        ends_on: "2031-08-31"
      }
    )
    |> render_submit()

    assert_patch(live, ~p"/admin/seasons")
    assert has_element?(live, "#flash-info")
    assert has_element?(live, "#seasons", "Saison d'été 2031")
    assert has_element?(live, "#seasons", "2031-06-01")
    assert has_element?(live, "#seasons", "2031-08-31")
  end

  test "lists existing seasons", %{conn: conn} do
    season = season_fixture(%{name: "Spring"})
    {:ok, live, _html} = live(conn, ~p"/admin/seasons")

    assert has_element?(live, "#seasons-#{season.id}", "Spring")
  end

  test "shows each season's status and riddle count", %{conn: conn} do
    Riddlr.Clock.Frozen.freeze(~U[2030-06-15 12:00:00Z])
    past = season_fixture(%{starts_on: ~D[2030-05-01], ends_on: ~D[2030-05-31]})
    current = season_fixture(%{starts_on: ~D[2030-06-01], ends_on: ~D[2030-06-30]})
    upcoming = season_fixture(%{starts_on: ~D[2030-07-01], ends_on: ~D[2030-07-31]})

    {:ok, live, _html} = live(conn, ~p"/admin/seasons")

    assert has_element?(live, "#seasons-#{past.id} [data-status=past]")
    assert has_element?(live, "#seasons-#{current.id} [data-status=current]")
    assert has_element?(live, "#seasons-#{upcoming.id} [data-status=upcoming]")
    assert has_element?(live, "#seasons-#{current.id} [data-role=riddle-count]", "0")
  end

  test "updates a season", %{conn: conn} do
    season = season_fixture(%{name: "Original"})
    {:ok, live, _html} = live(conn, ~p"/admin/seasons")

    live |> element("a[href='/admin/seasons/#{season.id}/edit']") |> render_click()

    live
    |> form("#season-form", season: %{name: "Renamed", ends_on: Date.add(season.ends_on, 1)})
    |> render_submit()

    assert_patch(live, ~p"/admin/seasons")
    assert has_element?(live, "#flash-info")
    assert has_element?(live, "#seasons-#{season.id}", "Renamed")
  end

  test "deletes a season", %{conn: conn} do
    season = season_fixture(%{})
    {:ok, live, _html} = live(conn, ~p"/admin/seasons")

    live |> element("#seasons-#{season.id} a[data-confirm]") |> render_click()

    refute has_element?(live, "#seasons-#{season.id}")
    assert has_element?(live, "#flash-info")
  end

  test "explains how the dates map to UTC times, above the date fields", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/admin/seasons/new")

    assert has_element?(live, "#season-form #season-dates-note + .adm-form-row")
  end

  test "shows an overlap error on the form", %{conn: conn} do
    season_fixture(%{starts_on: ~D[2031-01-01], ends_on: ~D[2031-01-31]})
    {:ok, live, _html} = live(conn, ~p"/admin/seasons/new")

    live
    |> form("#season-form",
      season: %{name: "Clash", starts_on: "2031-01-31", ends_on: "2031-02-28"}
    )
    |> render_submit()

    assert has_element?(live, "#season-form [name='season[ends_on]'][aria-invalid]")
  end

  describe "locked dates" do
    setup do
      Riddlr.Clock.Frozen.freeze(~U[2030-06-15 12:00:00Z])
      :ok
    end

    test "disables both dates of a past season, with a note", %{conn: conn} do
      past = season_fixture(%{starts_on: ~D[2030-05-01], ends_on: ~D[2030-05-31]})
      {:ok, live, _html} = live(conn, ~p"/admin/seasons/#{past.id}/edit")

      assert has_element?(live, "#season-form [name='season[starts_on]'][disabled]")
      assert has_element?(live, "#season-form [name='season[ends_on]'][disabled]")
      assert has_element?(live, "#season-locked-note")
      refute has_element?(live, "#season-form [name='season[name]'][disabled]")
    end

    test "disables only the start date of the current season", %{conn: conn} do
      current = season_fixture(%{starts_on: ~D[2030-06-01], ends_on: ~D[2030-06-30]})
      {:ok, live, _html} = live(conn, ~p"/admin/seasons/#{current.id}/edit")

      assert has_element?(live, "#season-form [name='season[starts_on]'][disabled]")
      refute has_element?(live, "#season-form [name='season[ends_on]'][disabled]")
      assert has_element?(live, "#season-locked-note")

      live |> form("#season-form", season: %{ends_on: "2030-07-10"}) |> render_submit()

      assert Riddlr.Games.get_season!(current.id).ends_on == ~D[2030-07-10]
    end

    test "leaves an upcoming season's dates open", %{conn: conn} do
      upcoming = season_fixture(%{starts_on: ~D[2030-07-01], ends_on: ~D[2030-07-31]})
      {:ok, live, _html} = live(conn, ~p"/admin/seasons/#{upcoming.id}/edit")

      refute has_element?(live, "#season-form [disabled]")
      refute has_element?(live, "#season-locked-note")
    end
  end

  describe "nav" do
    test "marks Seasons as the current nav item", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/admin/seasons")

      assert has_element?(live, ~s(.adm-nav a[aria-current="page"][href="/admin/seasons"]))
    end
  end

  describe "role taken away mid-session" do
    setup %{conn: conn} do
      season = season_fixture(%{name: "Kept"})
      {:ok, live, _html} = live(conn, ~p"/admin/seasons")
      %{season: season, live: live}
    end

    test "refuses a delete", %{admin: admin, season: season, live: live} do
      demote!(admin)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live |> element("#seasons-#{season.id} a[data-confirm]") |> render_click()

      assert Riddlr.Games.get_season!(season.id)
    end

    test "refuses a save", %{admin: admin, season: season, live: live} do
      live |> element("a[href='/admin/seasons/#{season.id}/edit']") |> render_click()
      demote!(admin)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live |> form("#season-form", season: %{name: "Taken"}) |> render_submit()

      assert Riddlr.Games.get_season!(season.id).name == "Kept"
    end
  end

  defp demote!(user), do: user |> Ecto.Changeset.change(role: :viewer) |> Riddlr.Repo.update!()

  # A moderator is an admin, just not one who manages riddles or seasons.
  describe "access" do
    setup do
      season = season_fixture(%{})

      %{
        paths: [~p"/admin/seasons", ~p"/admin/seasons/new", ~p"/admin/seasons/#{season.id}/edit"]
      }
    end

    test "turns a moderator away from every season page", %{conn: conn, paths: paths} do
      conn = log_in_user(conn, Riddlr.AccountsFixtures.user_fixture(%{role: :moderator}))

      for path <- paths do
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
      end
    end

    for role <- [:viewer, :player] do
      test "answers 404 to a #{role} on every season page", %{conn: conn, paths: paths} do
        conn = log_in_user(conn, Riddlr.AccountsFixtures.user_fixture(%{role: unquote(role)}))

        for path <- paths do
          assert_raise RiddlrWeb.NotFoundError, fn -> live(conn, path) end
        end
      end
    end

    for role <- [:editor, :super_admin] do
      test "lets a #{role} into every season page", %{conn: conn, paths: paths} do
        conn = log_in_user(conn, Riddlr.AccountsFixtures.user_fixture(%{role: unquote(role)}))

        for path <- paths do
          assert {:ok, _live, _html} = live(conn, path)
        end
      end
    end
  end
end
