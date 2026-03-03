defmodule RiddlrWeb.Admin.RiddleLive.FormComponentTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest
  import Ecto.Query
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

  describe "handle_event save with live_date change" do
    test "reschedules workers when live_date changes for published scheduled riddle", %{
      conn: conn,
      admin: admin
    } do
      old_live_date = ~U[2026-04-01 10:00:00Z]

      riddle =
        GamesFixtures.riddle_fixture(%{
          publish_status: "published",
          play_status: "closed"
        })

      # Schedule initial jobs
      {:ok, _} = Riddlr.Games.schedule_riddle(riddle, old_live_date)

      # Reload to get updated play_status
      riddle = Riddlr.Games.get_riddle!(riddle.id)
      assert riddle.play_status == "scheduled"

      # Verify initial jobs exist
      initial_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(initial_jobs) == 2

      # Change live_date through form
      new_live_date = ~U[2026-04-01 14:00:00Z]
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      view
      |> form("#riddle-form", riddle: %{live_date: format_datetime_local(new_live_date)})
      |> render_submit()

      # Verify old jobs cancelled
      old_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> where([j], j.scheduled_at == ^DateTime.add(old_live_date, -300))
        |> Riddlr.Repo.all()

      assert length(old_jobs) == 0

      # Verify new jobs scheduled
      new_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(new_jobs) == 2

      # Verify new job times (truncate to seconds for comparison)
      ready_job =
        Enum.find(new_jobs, &(&1.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker"))

      live_job =
        Enum.find(new_jobs, &(&1.worker == "Riddlr.Workers.LiveRiddleTransitionWorker"))

      assert DateTime.truncate(ready_job.scheduled_at, :second) ==
               DateTime.add(new_live_date, -300)

      assert DateTime.truncate(live_job.scheduled_at, :second) == new_live_date
    end

    test "does not reschedule when live_date unchanged", %{conn: conn, admin: admin} do
      live_date = ~U[2026-04-01 10:00:00Z]

      riddle =
        GamesFixtures.riddle_fixture(%{
          publish_status: "published",
          play_status: "closed"
        })

      {:ok, _} = Riddlr.Games.schedule_riddle(riddle, live_date)
      riddle = Riddlr.Games.get_riddle!(riddle.id)

      initial_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      initial_job_ids = Enum.map(initial_jobs, & &1.id)

      # Update without changing live_date
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      view
      |> form("#riddle-form", riddle: %{description: "Updated description"})
      |> render_submit()

      # Verify same jobs still exist (not rescheduled)
      current_jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      current_job_ids = Enum.map(current_jobs, & &1.id)

      assert Enum.sort(initial_job_ids) == Enum.sort(current_job_ids)
    end

    test "does not reschedule for draft riddles", %{conn: conn, admin: admin} do
      live_date = ~U[2026-04-01 10:00:00Z]

      riddle =
        GamesFixtures.riddle_fixture(%{
          publish_status: "draft",
          play_status: "closed",
          live_date: live_date
        })

      # Change live_date - play_status remains closed (it's now read-only in form)
      new_live_date = ~U[2026-04-01 14:00:00Z]
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      view
      |> form("#riddle-form",
        riddle: %{
          live_date: format_datetime_local(new_live_date)
        }
      )
      |> render_submit()

      # Verify no jobs scheduled (because draft, not published)
      jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(jobs) == 0
    end
  end

  describe "edit form play_status display" do
    test "shows current play status as read-only badge", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture(%{play_status: "scheduled"})
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      assert html =~ "Play Status"
      assert html =~ "scheduled"
      # Should NOT have a select input for play_status
      refute html =~ ~r/<select[^>]*name="riddle\[play_status\]"/
    end

    test "shows archive cooldown field when riddle is completed", %{conn: conn, admin: admin} do
      riddle =
        GamesFixtures.riddle_fixture(%{play_status: "completed", archive_cooldown_minutes: 5})

      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      assert html =~ "Archive Cooldown"
      assert html =~ "5"
    end

    test "shows archive cooldown field when riddle is archived", %{conn: conn, admin: admin} do
      riddle =
        GamesFixtures.riddle_fixture(%{play_status: "archived", archive_cooldown_minutes: 10})

      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      assert html =~ "Archive Cooldown"
      assert html =~ "10"
    end

    test "does not show archive cooldown field for non-completed riddles", %{
      conn: conn,
      admin: admin
    } do
      riddle = GamesFixtures.riddle_fixture(%{play_status: "live"})
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      refute html =~ "Archive Cooldown"
    end
  end

  # Helper to format datetime for datetime-local input
  defp format_datetime_local(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
  end
end
