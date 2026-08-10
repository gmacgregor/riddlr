defmodule Riddlr.Games.SaveRiddleTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Ecto.Query
  import Riddlr.GamesFixtures

  alias Riddlr.Games
  alias Riddlr.Games.Riddle

  describe "save_riddle/2 plain write" do
    test "inserts a new riddle" do
      attrs = %{
        name: unique_riddle_name(),
        description: "What has keys but no locks?",
        answers: ["keyboard"],
        solve_time: 60,
        category_id: category_fixture().id
      }

      assert {:ok, %Riddle{} = riddle} = Games.save_riddle(%Riddle{}, attrs)
      assert riddle.id
      assert riddle.play_status == "closed"
      assert riddle.publish_status == "draft"
      assert %Riddlr.Games.Category{} = riddle.category
    end

    test "updates an existing riddle" do
      riddle = riddle_fixture()

      assert {:ok, %Riddle{} = updated} = Games.save_riddle(riddle, %{name: "Renamed"})
      assert updated.name == "Renamed"
      assert Repo.reload(riddle).name == "Renamed"
    end

    test "returns {:error, changeset} on invalid data" do
      riddle = riddle_fixture()

      assert {:error, %Ecto.Changeset{}} = Games.save_riddle(riddle, %{name: nil})
      assert Repo.reload(riddle).name == riddle.name
    end
  end

  describe "save_riddle/2 :schedule" do
    test "schedules a closed published riddle with a future live date" do
      riddle = riddle_fixture(%{publish_status: "published"})
      live_date = future(3600)

      assert {:ok, saved} = Games.save_riddle(riddle, %{"live_date" => live_date})
      assert saved.play_status == "scheduled"
      assert DateTime.compare(saved.live_date, live_date) == :eq
    end

    test "enqueues the ready and live jobs in the same transaction" do
      riddle = riddle_fixture(%{publish_status: "published", ready_before_seconds: 20})
      live_date = future(3600)

      assert {:ok, saved} = Games.save_riddle(riddle, %{"live_date" => live_date})

      assert [ready] = pending_jobs(saved.id, Riddlr.Workers.ReadyRiddleTransitionWorker)
      assert [live] = pending_jobs(saved.id, Riddlr.Workers.LiveRiddleTransitionWorker)
      assert DateTime.diff(ready.scheduled_at, live_date, :second) == -20
      assert DateTime.compare(live.scheduled_at, live_date) == :eq
    end

    test "schedules when the same save also publishes the riddle" do
      riddle = riddle_fixture()
      live_date = future(3600)

      assert {:ok, saved} =
               Games.save_riddle(riddle, %{
                 "publish_status" => "published",
                 "live_date" => live_date
               })

      assert saved.play_status == "scheduled"
      assert length(pending_jobs(saved.id)) == 2
    end

    test "broadcasts :riddle_scheduled with the category preloaded" do
      riddle = riddle_fixture(%{publish_status: "published"})
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:scheduled")

      assert {:ok, _} = Games.save_riddle(riddle, %{"live_date" => future(3600)})

      assert_receive {:riddle_scheduled, %{id: ^riddle_id} = broadcast}
      assert %Riddlr.Games.Category{} = broadcast.category
    end

    test "does not schedule a draft riddle" do
      riddle = riddle_fixture()

      assert {:ok, saved} = Games.save_riddle(riddle, %{"live_date" => future(3600)})
      assert saved.play_status == "closed"
      assert pending_jobs(saved.id) == []
    end

    test "does not schedule a live date in the past" do
      riddle = riddle_fixture(%{publish_status: "published"})

      assert {:ok, saved} = Games.save_riddle(riddle, %{"live_date" => future(-3600)})
      assert saved.play_status == "closed"
      assert pending_jobs(saved.id) == []
    end

    test "does not schedule without a live date" do
      riddle = riddle_fixture(%{publish_status: "published"})

      assert {:ok, saved} = Games.save_riddle(riddle, %{"name" => "Renamed"})
      assert saved.play_status == "closed"
      assert pending_jobs(saved.id) == []
    end

    test "does not schedule a riddle that is already live" do
      riddle = riddle_fixture(%{publish_status: "published", play_status: "live"})

      assert {:ok, saved} = Games.save_riddle(riddle, %{"live_date" => future(3600)})
      assert saved.play_status == "live"
      assert pending_jobs(saved.id) == []
    end
  end

  describe "save_riddle/2 :reschedule" do
    test "moves the jobs when the live date changes" do
      riddle = scheduled_riddle_fixture(%{live_date: future(3600)})
      [old_ready, old_live] = pending_jobs(riddle.id) |> Enum.sort_by(& &1.id)
      new_live_date = future(7200)

      assert {:ok, saved} = Games.save_riddle(riddle, %{"live_date" => new_live_date})
      assert saved.play_status == "scheduled"

      assert [ready] = pending_jobs(saved.id, Riddlr.Workers.ReadyRiddleTransitionWorker)
      assert [live] = pending_jobs(saved.id, Riddlr.Workers.LiveRiddleTransitionWorker)
      refute ready.id in [old_ready.id, old_live.id]

      assert DateTime.diff(ready.scheduled_at, new_live_date, :second) ==
               -saved.ready_before_seconds

      assert DateTime.compare(live.scheduled_at, new_live_date) == :eq
    end

    test "moves the ready job when only the lead time changes" do
      riddle = scheduled_riddle_fixture(%{live_date: future(3600), ready_before_seconds: 600})

      assert {:ok, saved} = Games.save_riddle(riddle, %{"ready_before_seconds" => 1200})
      assert saved.ready_before_seconds == 1200

      assert [ready] = pending_jobs(saved.id, Riddlr.Workers.ReadyRiddleTransitionWorker)
      assert DateTime.diff(ready.scheduled_at, saved.live_date, :second) == -1200
    end

    test "reschedules a riddle whose lobby is already open" do
      riddle = scheduled_riddle_fixture(%{live_date: future(3600)})
      {:ok, _} = Games.transition(riddle.id, :ready)
      riddle = Games.get_riddle!(riddle.id)

      assert {:ok, saved} = Games.save_riddle(riddle, %{"live_date" => future(7200)})
      assert saved.play_status == "ready"
      assert length(pending_jobs(saved.id)) == 2
    end

    test "leaves the jobs alone when nothing about the schedule changed" do
      riddle = scheduled_riddle_fixture(%{live_date: future(3600)})
      job_ids = riddle.id |> pending_jobs() |> Enum.map(& &1.id) |> Enum.sort()

      assert {:ok, saved} = Games.save_riddle(riddle, %{"name" => "Renamed"})
      assert saved.id |> pending_jobs() |> Enum.map(& &1.id) |> Enum.sort() == job_ids
    end

    test "broadcasts :riddle_rescheduled" do
      riddle = scheduled_riddle_fixture(%{live_date: future(3600)})
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:scheduled")

      assert {:ok, _} = Games.save_riddle(riddle, %{"live_date" => future(7200)})

      assert_receive {:riddle_rescheduled, %{id: ^riddle_id}}
    end
  end

  describe "save_riddle/2 :unschedule" do
    test "rolling a scheduled riddle back to draft closes it and cancels its jobs" do
      riddle = scheduled_riddle_fixture()

      assert {:ok, saved} = Games.save_riddle(riddle, %{"publish_status" => "draft"})
      assert saved.publish_status == "draft"
      assert saved.play_status == "closed"
      assert pending_jobs(saved.id) == []
    end

    test "rolling back an open lobby closes it and cancels its jobs" do
      riddle = scheduled_riddle_fixture()
      {:ok, _} = Games.transition(riddle.id, :ready)
      riddle = Games.get_riddle!(riddle.id)

      assert {:ok, saved} = Games.save_riddle(riddle, %{"publish_status" => "draft"})
      assert saved.play_status == "closed"
      assert pending_jobs(saved.id) == []
    end

    test "broadcasts :riddle_unscheduled" do
      riddle = scheduled_riddle_fixture()
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:scheduled")

      assert {:ok, _} = Games.save_riddle(riddle, %{"publish_status" => "draft"})

      assert_receive {:riddle_unscheduled, %{id: ^riddle_id}}
    end

    test "a draft riddle that was never scheduled is a plain write" do
      riddle = riddle_fixture(%{publish_status: "published"})

      assert {:ok, saved} = Games.save_riddle(riddle, %{"publish_status" => "draft"})
      assert saved.play_status == "closed"
      assert pending_jobs(saved.id) == []
    end
  end

  describe "save_riddle/2 broadcasts" do
    test "every successful save announces :riddle_saved" do
      riddle = riddle_fixture()
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:changed")

      assert {:ok, _} = Games.save_riddle(riddle, %{"name" => "Renamed"})

      assert_receive {:riddle_saved, %{id: ^riddle_id, name: "Renamed"} = broadcast}
      assert %Riddlr.Games.Category{} = broadcast.category
    end

    test "a failed save announces nothing" do
      riddle = riddle_fixture()
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:changed")

      assert {:error, _} = Games.save_riddle(riddle, %{"name" => nil})

      refute_receive {:riddle_saved, %{id: ^riddle_id}}
    end
  end

  defp future(seconds),
    do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)

  defp pending_jobs(riddle_id, worker \\ nil) do
    Oban.Job
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle_id)))
    |> where([j], j.state in ["available", "scheduled", "retryable"])
    |> then(fn query ->
      if worker, do: where(query, [j], j.worker == ^inspect(worker)), else: query
    end)
    |> Repo.all()
  end
end
