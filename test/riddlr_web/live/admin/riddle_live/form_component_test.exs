defmodule RiddlrWeb.Admin.RiddleLive.FormComponentTest do
  use RiddlrWeb.ConnCase
  use Oban.Testing, repo: Riddlr.Repo
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
             |> render_click() =~ "New riddle"

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

  describe "Create riddle with auto-scheduling" do
    setup do
      category =
        Riddlr.Repo.get_by(Riddlr.Games.Category, name: "logic") ||
          Riddlr.Repo.insert!(%Riddlr.Games.Category{name: "logic"})

      %{category: category}
    end

    test "auto-schedules when created with published status and future live_date", %{
      conn: conn,
      admin: admin,
      category: category
    } do
      future_live_date = DateTime.add(DateTime.utc_now(), 3600, :second)

      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")
      index_live |> element("a", "New Riddle") |> render_click()

      index_live
      |> form("#riddle-form",
        riddle: %{
          name: "Auto-schedule test",
          description: "Will this be scheduled?",
          answers: "keyboard\na keyboard",
          solve_time: 120,
          category_id: category.id,
          publish_status: "published",
          live_date: format_datetime_local(future_live_date)
        }
      )
      |> render_submit()

      riddle = Riddlr.Repo.get_by(Riddlr.Games.Riddle, name: "Auto-schedule test")
      assert riddle.play_status == "scheduled"
      assert riddle.publish_status == "published"

      jobs =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.all()

      assert length(jobs) == 2
    end

    test "does not schedule when created with draft status", %{
      conn: conn,
      admin: admin,
      category: category
    } do
      future_live_date = DateTime.add(DateTime.utc_now(), 3600, :second)

      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")
      index_live |> element("a", "New Riddle") |> render_click()

      index_live
      |> form("#riddle-form",
        riddle: %{
          name: "Draft test riddle",
          description: "Stays closed",
          answers: "keyboard",
          solve_time: 120,
          category_id: category.id,
          publish_status: "draft",
          live_date: format_datetime_local(future_live_date)
        }
      )
      |> render_submit()

      riddle = Riddlr.Repo.get_by(Riddlr.Games.Riddle, name: "Draft test riddle")
      assert riddle.play_status == "closed"
    end
  end

  describe "Edit riddle" do
    test "updates riddle with valid data", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture()
      conn = log_in_user(conn, admin)
      {:ok, index_live, _html} = live(conn, ~p"/admin/riddles")

      assert index_live
             |> element("#riddles-#{riddle.id} a", "Edit")
             |> render_click() =~ "Edit riddle"

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
      old_live_date = DateTime.add(DateTime.utc_now(), 86_400, :second)

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
      new_live_date = DateTime.add(DateTime.utc_now(), 172_800, :second)
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
        |> where(
          [j],
          j.scheduled_at == ^DateTime.add(old_live_date, -riddle.ready_before_seconds)
        )
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
               DateTime.add(new_live_date, -riddle.ready_before_seconds)
               |> DateTime.truncate(:second)

      assert DateTime.truncate(live_job.scheduled_at, :second) ==
               DateTime.truncate(new_live_date, :second)
    end

    test "does not reschedule when live_date unchanged", %{conn: conn, admin: admin} do
      live_date = DateTime.add(DateTime.utc_now(), 86_400, :second)

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

  describe "handle_event save with ready_before_seconds change" do
    test "reschedules when ready_before_seconds increases such that ready time moves to past", %{
      conn: conn,
      admin: admin
    } do
      # live_date = 30 min from now
      # initial ready_before_seconds = 600 (10 min) → ready_time = 20 min from now
      # new ready_before_seconds = 3600 (1h)       → ready_time = now - 30 min (past)
      live_date = DateTime.add(DateTime.utc_now(), 1800, :second)

      riddle =
        GamesFixtures.riddle_fixture(%{
          publish_status: "published",
          play_status: "closed",
          ready_before_seconds: 600
        })

      {:ok, _} = Riddlr.Games.schedule_riddle(riddle, live_date)
      riddle = Riddlr.Games.get_riddle!(riddle.id)
      assert riddle.play_status == "scheduled"

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      view
      |> form("#riddle-form", riddle: %{ready_before_seconds: 3600})
      |> render_submit()

      # ready_before_seconds should be persisted
      updated_riddle = Riddlr.Games.get_riddle!(riddle.id)
      assert updated_riddle.ready_before_seconds == 3600

      # Ready job rescheduled — new scheduled_at is in the past so Oban marks it available
      ready_job =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
        |> where([j], j.state in ["available", "scheduled"])
        |> Riddlr.Repo.one()

      assert ready_job != nil
      assert DateTime.compare(ready_job.scheduled_at, DateTime.utc_now()) == :lt
    end

    test "reschedules when ready_before_seconds changes and new ready time remains future", %{
      conn: conn,
      admin: admin
    } do
      # live_date = 3h from now
      # initial ready_before_seconds = 7200 (2h) → ready_time = 1h from now
      # new ready_before_seconds = 3600 (1h)     → ready_time = 2h from now (still future)
      live_date = DateTime.add(DateTime.utc_now(), 10_800, :second)

      riddle =
        GamesFixtures.riddle_fixture(%{
          publish_status: "published",
          play_status: "closed",
          ready_before_seconds: 7200
        })

      {:ok, _} = Riddlr.Games.schedule_riddle(riddle, live_date)
      riddle = Riddlr.Games.get_riddle!(riddle.id)
      assert riddle.play_status == "scheduled"

      initial_ready_job =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.one()

      assert initial_ready_job != nil
      initial_ready_id = initial_ready_job.id

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      view
      |> form("#riddle-form", riddle: %{ready_before_seconds: 3600})
      |> render_submit()

      new_ready_job =
        Oban.Job
        |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
        |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
        |> where([j], j.state in ["scheduled", "available"])
        |> Riddlr.Repo.one()

      # Old job cancelled, new job created at updated time
      assert new_ready_job != nil
      assert new_ready_job.id != initial_ready_id

      expected_ready_at = live_date |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      assert DateTime.truncate(new_ready_job.scheduled_at, :second) == expected_ready_at
    end
  end

  describe "edit form play_status display" do
    test "shows current play status as read-only badge", %{conn: conn, admin: admin} do
      riddle = GamesFixtures.riddle_fixture(%{play_status: "scheduled"})
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      assert html =~ "Play status"
      assert html =~ "scheduled"
      # Should NOT have a select input for play_status
      refute html =~ ~r/<select[^>]*name="riddle\[play_status\]"/
    end

    test "shows archive cooldown field when riddle is completed", %{conn: conn, admin: admin} do
      riddle =
        GamesFixtures.riddle_fixture(%{play_status: "completed", archive_after_seconds: 5})

      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      assert html =~ "Archive cool off"
      assert html =~ "5"
    end

    test "shows archive cooldown field when riddle is archived", %{conn: conn, admin: admin} do
      riddle =
        GamesFixtures.riddle_fixture(%{play_status: "archived", archive_after_seconds: 10})

      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      assert html =~ "Archive cool off"
      assert html =~ "10"
    end

    test "archive cooldown field is always visible", %{
      conn: conn,
      admin: admin
    } do
      riddle = GamesFixtures.riddle_fixture(%{play_status: "live"})
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

      assert html =~ "Archive cool off"
    end
  end

  # Helper to format datetime for datetime-local input.
  # Converts UTC to Eastern time first, mimicking what a browser sends
  # when the admin's timezone is America/New_York.
  defp format_datetime_local(datetime) do
    {:ok, eastern} = DateTime.shift_zone(datetime, "America/New_York")
    Calendar.strftime(eastern, "%Y-%m-%dT%H:%M:%S")
  end
end
