defmodule Riddlr.Games.TransitionTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Riddlr.GamesFixtures

  alias Riddlr.Games

  defp published(attrs), do: riddle_fixture(Map.put(attrs, :publish_status, "published"))

  describe "transition/3 to :ready" do
    test "moves a scheduled riddle to ready" do
      riddle = published(%{play_status: "scheduled"})

      assert {:ok, updated} = Games.transition(riddle.id, :ready)
      assert updated.play_status == "ready"
      assert Repo.reload(riddle).play_status == "ready"
    end

    test "broadcasts :riddle_ready with the category preloaded" do
      riddle = published(%{play_status: "scheduled"})
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:ready")

      assert {:ok, _} = Games.transition(riddle.id, :ready)

      assert_receive {:riddle_ready, %{id: ^riddle_id} = broadcast}
      assert %Riddlr.Games.Category{} = broadcast.category
    end
  end

  describe "transition/3 guards" do
    test "returns {:error, :not_found} for an unknown riddle" do
      assert {:error, :not_found} = Games.transition(-1, :ready)
    end

    test "returns {:unpublished, status} for a draft riddle" do
      riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "draft"})

      assert {:unpublished, "draft"} = Games.transition(riddle.id, :ready)
      assert Repo.reload(riddle).play_status == "scheduled"
    end

    test "returns {:invalid, from, to} for a forbidden transition" do
      riddle = published(%{play_status: "closed"})

      assert {:invalid, "closed", :ready} = Games.transition(riddle.id, :ready)
      assert Repo.reload(riddle).play_status == "closed"
    end

    test "a repeated transition is invalid rather than a no-op" do
      riddle = published(%{play_status: "scheduled"})

      assert {:ok, _} = Games.transition(riddle.id, :ready)
      assert {:invalid, "ready", :ready} = Games.transition(riddle.id, :ready)
    end

    test "does not broadcast when the transition is rejected" do
      riddle = published(%{play_status: "closed"})
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:ready")

      assert {:invalid, _, _} = Games.transition(riddle.id, :ready)

      refute_receive {:riddle_ready, %{id: ^riddle_id}}
    end
  end

  describe "transition/3 to :live" do
    test "moves a ready riddle to live and broadcasts" do
      riddle = published(%{play_status: "ready"})
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:live")

      assert {:ok, updated} = Games.transition(riddle.id, :live)
      assert updated.play_status == "live"
      assert_receive {:riddle_live, %{id: ^riddle_id}}
    end

    test "enqueues the complete job after solve_time" do
      riddle = published(%{play_status: "ready", solve_time: 90})

      assert {:ok, _} = Games.transition(riddle.id, :live)

      assert_enqueued(
        worker: Riddlr.Workers.CompleteRiddleWorker,
        args: %{riddle_id: riddle.id}
      )
    end

    test "always enqueues the complete job" do
      riddle = published(%{play_status: "ready"})

      assert {:ok, _} = Games.transition(riddle.id, :live)

      assert_enqueued(worker: Riddlr.Workers.CompleteRiddleWorker)
    end
  end

  describe "transition/3 to :completed" do
    test "moves a live riddle to completed and broadcasts" do
      riddle = published(%{play_status: "live"})
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")

      assert {:ok, updated} = Games.transition(riddle.id, :completed)
      assert updated.play_status == "completed"
      assert_receive {:riddle_completed, %{id: ^riddle_id}}
    end

    test "stores the whitelisted stats and ignores anything else" do
      riddle = published(%{play_status: "live"})
      user = Riddlr.AccountsFixtures.user_fixture()

      stats = %{
        first_solver_id: user.id,
        first_solve_time: 42,
        completion_rate: 75.0,
        play_status: "archived"
      }

      assert {:ok, updated} = Games.transition(riddle.id, :completed, stats)
      assert updated.play_status == "completed"
      assert updated.first_solver_id == user.id
      assert updated.first_solve_time == 42
      assert updated.completion_rate == 75.0
    end

    test "enqueues the archive job after archive_after_seconds" do
      riddle = published(%{play_status: "live", archive_after_seconds: 30})

      assert {:ok, _} = Games.transition(riddle.id, :completed)

      assert_enqueued(
        worker: Riddlr.Workers.ArchiveRiddleTransitionWorker,
        args: %{riddle_id: riddle.id}
      )
    end

    test "a live riddle completes without a solver" do
      riddle = published(%{play_status: "live"})

      assert {:ok, updated} = Games.transition(riddle.id, :completed)
      assert updated.play_status == "completed"
    end

    test "completes with a solver supplied" do
      riddle = published(%{play_status: "live"})
      user = Riddlr.AccountsFixtures.user_fixture()

      assert {:ok, updated} = Games.transition(riddle.id, :completed, %{first_solver_id: user.id})
      assert updated.play_status == "completed"
    end
  end

  describe "transition/3 to :archived" do
    test "moves a completed riddle to archived and broadcasts" do
      riddle = published(%{play_status: "completed"})
      riddle_id = riddle.id
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")

      assert {:ok, updated} = Games.transition(riddle.id, :archived)
      assert updated.play_status == "archived"
      assert_receive {:riddle_archived, %{id: ^riddle_id}}
    end

    test "clears the riddle's ETS rows" do
      riddle = published(%{play_status: "completed"})
      user_id = :erlang.unique_integer([:positive])

      :ets.insert(
        :riddle_answers,
        {{riddle.id, user_id}, "answer", System.monotonic_time(:microsecond), true, nil}
      )

      :ets.insert(:answer_cooldowns, {{riddle.id, user_id}, System.monotonic_time(:microsecond)})

      assert {:ok, _} = Games.transition(riddle.id, :archived)

      assert :ets.lookup(:riddle_answers, {riddle.id, user_id}) == []
      assert :ets.lookup(:answer_cooldowns, {riddle.id, user_id}) == []
    end
  end
end
