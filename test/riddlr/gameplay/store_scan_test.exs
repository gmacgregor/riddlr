defmodule Riddlr.Gameplay.StoreScanTest do
  # Fills the shared tables with 100k rows, so it must run alone.
  use ExUnit.Case, async: false

  alias Riddlr.Accounts.User
  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Store
  alias Riddlr.Games.Riddle

  @tables ~w(riddle_answers riddle_players riddle_counters answer_cooldowns)

  defp unique_id, do: :erlang.unique_integer([:positive])

  # ETS charges the caller reductions per row it walks, so a read that scans
  # other riddles' rows costs more as they grow. Keyed and prefix reads do not.
  describe "a riddle's reads and writes do not walk other riddles' rows" do
    setup do
      rid = unique_id()
      riddle = %Riddle{id: rid, play_status: "live", answers: ["keyboard"], solve_time: 600}
      riddle = %{riddle | live_date: DateTime.add(Riddlr.Clock.utc_now(), -10, :second)}

      for _ <- 1..20, do: seed(rid)
      solver = unique_id()
      {:ok, _} = Store.record(answer(rid, solver, correct: true))

      others = Enum.map(1..100, fn _ -> unique_id() end)
      on_exit(fn -> Enum.each([rid | others], &Store.cleanup_riddle/1) end)

      %{riddle: riddle, rid: rid, solver: solver, others: others}
    end

    test "costs about the same with 1k or 100k other rows", ctx do
      fill(ctx.others, 10)
      small = costs(ctx)

      fill(ctx.others, 990)
      large = costs(ctx)

      for {op, cost} <- small do
        assert large[op] / cost < 1.5,
               "#{op}: #{cost} reductions at 1k rows, #{large[op]} at 100k"
      end
    end
  end

  test "only Store names the game tables" do
    store = Path.expand("lib/riddlr/gameplay/store.ex")
    pattern = ~r/:(#{Enum.join(@tables, "|")})\b/

    offenders =
      for path <- Path.wildcard("{lib,test}/**/*.{ex,exs}"),
          Path.expand(path) not in [store, Path.expand(__ENV__.file)],
          File.read!(path) =~ pattern,
          do: path

    assert offenders == []
  end

  defp costs(ctx) do
    %{
      submit_answer: cost(fn -> Gameplay.submit_answer(ctx.riddle, user(), "nope") end),
      solved_count: cost(fn -> Gameplay.solved_count(ctx.rid) end),
      live_solve_for: cost(fn -> Gameplay.live_solve_for(ctx.rid, ctx.solver) end),
      get_answers: cost(fn -> Gameplay.get_answers(ctx.rid, 100) end),
      solve_rows: cost(fn -> Gameplay.solve_rows(ctx.rid) end),
      entry_rows: cost(fn -> Gameplay.entry_rows(ctx.rid) end),
      cleanup_riddle: cost(fn -> Gameplay.cleanup_riddle(unique_id()) end)
    }
  end

  # The least of several runs, to shed scheduler noise.
  defp cost(fun) do
    Enum.min(
      for _ <- 1..5 do
        {:reductions, before} = Process.info(self(), :reductions)
        fun.()
        {:reductions, after_run} = Process.info(self(), :reductions)
        after_run - before
      end
    )
  end

  defp fill(riddle_ids, per_riddle) do
    for rid <- riddle_ids, _ <- 1..per_riddle, do: seed(rid)
  end

  defp seed(rid), do: {:ok, _} = Store.record(answer(rid, unique_id()))

  defp answer(rid, uid, opts \\ []) do
    Answer.new(rid, %{id: uid, username: "u"}, "guess", opts)
  end

  defp user, do: %User{id: unique_id(), username: "u", account_status: :active}
end
