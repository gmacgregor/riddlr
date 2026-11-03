defmodule Riddlr.Gameplay.StoreTest do
  # The tables are shared by the whole node. Unique riddle ids keep tests apart,
  # but the concurrency tests below flood them, so run alone.
  use ExUnit.Case, async: false

  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Store

  defp unique_id, do: :erlang.unique_integer([:positive])

  defp answer(rid, uid, opts \\ []) do
    {text, opts} = Keyword.pop(opts, :text, "guess")
    Answer.new(rid, %{id: uid, username: "user#{uid}"}, text, opts)
  end

  describe "record/1" do
    test "stores a wrong guess with no placement" do
      rid = unique_id()
      uid = unique_id()

      assert {:ok, nil} = Store.record(answer(rid, uid))
      assert Store.guessed?(rid, uid)
      refute Store.solved?(rid, uid)
      assert Store.answer_count(rid) == 1
      assert Store.player_count(rid) == 1
      assert Store.solved_count(rid) == 0
    end

    test "places correct answers in the order they are recorded" do
      rid = unique_id()
      [a, b] = [unique_id(), unique_id()]

      assert {:ok, 1} = Store.record(answer(rid, a, correct: true, offset_ms: 900))
      assert {:ok, 2} = Store.record(answer(rid, b, correct: true, offset_ms: 400))

      assert Store.solve_for(rid, a) == %{placement: 1, offset_ms: 900}
      assert Store.solve_for(rid, b) == %{placement: 2, offset_ms: 400}
      assert Store.solved_count(rid) == 2
    end

    test "refuses a second correct answer from the same player" do
      rid = unique_id()
      uid = unique_id()

      assert {:ok, 1} = Store.record(answer(rid, uid, correct: true))
      assert {:error, :already_solved} = Store.record(answer(rid, uid, correct: true))

      assert Store.solved_count(rid) == 1
      assert Store.answer_count(rid) == 1
    end

    test "counts each player once however many times they guess" do
      rid = unique_id()
      uid = unique_id()

      for _ <- 1..3, do: Store.record(answer(rid, uid))

      assert Store.player_count(rid) == 1
      assert Store.answer_count(rid) == 3
    end

    test "concurrent correct answers by distinct players get placements 1..N" do
      rid = unique_id()

      placements =
        1..500
        |> Task.async_stream(fn _ -> Store.record(answer(rid, unique_id(), correct: true)) end,
          max_concurrency: 50
        )
        |> Enum.map(fn {:ok, {:ok, placement}} -> placement end)

      assert Enum.sort(placements) == Enum.to_list(1..500)
      assert Store.solved_count(rid) == 500
      assert rid |> Store.solves() |> Enum.map(&elem(&1, 1)) == Enum.to_list(1..500)
    end

    test "concurrent correct answers by the same player give one solve" do
      rid = unique_id()
      uid = unique_id()

      results =
        1..20
        |> Task.async_stream(fn _ -> Store.record(answer(rid, uid, correct: true)) end,
          max_concurrency: 20
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, 1}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :already_solved})) == 19
      assert Store.solved_count(rid) == 1
    end
  end

  describe "counts" do
    test "are 0 for an unknown riddle" do
      rid = unique_id()

      assert Store.answer_count(rid) == 0
      assert Store.player_count(rid) == 0
      assert Store.solved_count(rid) == 0
    end
  end

  describe "recent_answers/2" do
    test "returns answers newest first, with usernames and placements" do
      rid = unique_id()
      [a, b] = [unique_id(), unique_id()]

      Store.record(answer(rid, a, text: "first", timestamp: 1))
      Store.record(answer(rid, b, text: "second", timestamp: 2, correct: true))

      assert [
               %Answer{user_id: ^b, text: "second", correct: true, placement: 1} = newest,
               %Answer{user_id: ^a, text: "first", correct: false, placement: nil}
             ] = Store.recent_answers(rid)

      assert newest.username == "user#{b}"
      assert newest.id == Answer.id(rid, b, 2)
    end

    test "takes only the newest `limit` answers" do
      rid = unique_id()

      for ts <- 1..5, do: Store.record(answer(rid, unique_id(), timestamp: ts))

      assert rid |> Store.recent_answers(2) |> Enum.map(& &1.timestamp) == [5, 4]
    end

    test "is empty for an unknown riddle" do
      assert Store.recent_answers(unique_id(), 10) == []
    end
  end

  describe "solves/1 and players/1" do
    test "list solvers by placement and every player who guessed" do
      rid = unique_id()
      [a, b, c] = [unique_id(), unique_id(), unique_id()]

      Store.record(answer(rid, c))
      Store.record(answer(rid, b, correct: true, offset_ms: 20))
      Store.record(answer(rid, a, correct: true, offset_ms: 10))

      assert Store.solves(rid) == [{b, 1, 20}, {a, 2, 10}]
      assert rid |> Store.players() |> Enum.sort() == Enum.sort([a, b, c])
    end
  end

  describe "claim_cooldown/2" do
    test "refuses a second claim inside the window" do
      key = {unique_id(), unique_id()}

      assert :ok = Store.claim_cooldown(key, 1_000_000)
      assert {:error, :cooldown} = Store.claim_cooldown(key, 1_000_000)
      assert :ok = Store.claim_cooldown(key, 0)
    end
  end

  describe "cleanup_riddle/1" do
    test "drops every row of the riddle and leaves others alone" do
      [rid, other] = [unique_id(), unique_id()]
      uid = unique_id()

      for r <- [rid, other] do
        Store.record(answer(r, uid, correct: true))
        Store.claim_cooldown({r, uid}, 1_000_000)
        Store.claim_cooldown({r, {:chat, uid}}, 1_000_000)
      end

      Store.cleanup_riddle(rid)

      assert Store.recent_answers(rid) == []
      refute Store.guessed?(rid, uid)
      assert Store.answer_count(rid) == 0
      assert Store.solved_count(rid) == 0
      assert :ok = Store.claim_cooldown({rid, uid}, 1_000_000)
      assert :ok = Store.claim_cooldown({rid, {:chat, uid}}, 1_000_000)

      assert [_] = Store.recent_answers(other)
      assert Store.solved_count(other) == 1
      assert {:error, :cooldown} = Store.claim_cooldown({other, uid}, 1_000_000)
    end
  end
end
