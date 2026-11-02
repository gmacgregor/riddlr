defmodule Riddlr.Gameplay.ModerationDropTest do
  # Fills the node's moderation supervisor, so must run alone.
  use ExUnit.Case, async: false

  alias Riddlr.Accounts.User
  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.Store
  alias Riddlr.Games.Riddle

  setup do
    test = self()
    handler = "moderation-dropped-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:riddlr, :moderation, :dropped],
      fn _event, measurements, meta, _config -> send(test, {:dropped, measurements, meta}) end,
      nil
    )

    rid = :erlang.unique_integer([:positive])
    riddle = %Riddle{id: rid, play_status: "live", answers: ["keyboard"], solve_time: 600}
    riddle = %{riddle | live_date: DateTime.add(Riddlr.Clock.utc_now(), -10, :second)}

    on_exit(fn ->
      :telemetry.detach(handler)
      Store.cleanup_riddle(rid)
    end)

    %{riddle: riddle}
  end

  test "a full supervisor skips moderation and the guess still lands", %{riddle: riddle} do
    blockers = fill_supervisor()

    assert Gameplay.submit_answer(riddle, user(), "nope") == :incorrect
    assert_receive {:dropped, %{count: 1}, %{riddle_id: id}} when id == riddle.id

    release(blockers)

    assert Gameplay.submit_answer(riddle, user(), "nope again") == :incorrect
    refute_receive {:dropped, _, _}
  end

  # Starts tasks that wait for :go until the supervisor refuses one.
  defp fill_supervisor(blockers \\ []) do
    case Task.Supervisor.start_child(Riddlr.ModerationSupervisor, fn ->
           receive do
             :go -> :ok
           end
         end) do
      {:ok, pid} -> fill_supervisor([pid | blockers])
      {:error, :max_children} -> blockers
    end
  end

  defp release(blockers) do
    for pid <- blockers do
      ref = Process.monitor(pid)
      send(pid, :go)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  defp user,
    do: %User{id: :erlang.unique_integer([:positive]), username: "u", account_status: :active}
end
