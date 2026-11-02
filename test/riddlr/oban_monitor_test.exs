defmodule Riddlr.ObanMonitorTest do
  use Riddlr.DataCase, async: true

  alias Riddlr.ObanMonitor
  alias Riddlr.Workers.{ArchiveRiddleTransitionWorker, CompleteRiddleWorker}

  test "stats/0 counts jobs by state, queue and worker" do
    {:ok, _} = Oban.insert(CompleteRiddleWorker.new(%{"riddle_id" => 1}))
    {:ok, _} = Oban.insert(CompleteRiddleWorker.new(%{"riddle_id" => 2}, schedule_in: 60))
    {:ok, _} = Oban.insert(ArchiveRiddleTransitionWorker.new(%{"riddle_id" => 1}))

    stats = ObanMonitor.stats()

    assert stats.total == 3
    assert stats.by_state == %{"available" => 2, "scheduled" => 1}
    assert stats.by_queue == %{"game_lifecycle" => 3}

    assert stats.by_worker == %{
             inspect(CompleteRiddleWorker) => 2,
             inspect(ArchiveRiddleTransitionWorker) => 1
           }
  end

  test "stats/0 is all zeros with no jobs" do
    assert ObanMonitor.stats() == %{total: 0, by_state: %{}, by_queue: %{}, by_worker: %{}}
  end
end
