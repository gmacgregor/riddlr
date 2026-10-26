defmodule Riddlr.Games.RiddleNumberConcurrencyTest do
  # Not async, and outside the sandbox: the advisory lock only matters when
  # two transactions run on two real connections at once. Rows are committed,
  # so the test deletes them when it is done. Sync tests run after every async
  # test, so no other test sees these rows.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Riddlr.Games
  alias Riddlr.Games.{Category, Riddle}
  alias Riddlr.Repo

  setup do
    {category, riddles} =
      Sandbox.unboxed_run(Repo, fn ->
        category = Repo.insert!(%Category{name: "concurrency #{System.unique_integer()}"})

        riddles =
          for _ <- 1..2 do
            Repo.insert!(%Riddle{
              name: "Riddle #{System.unique_integer([:positive])}",
              description: "What has keys but no locks?",
              answers: ["keyboard"],
              category_id: category.id,
              publish_status: "published",
              play_status: "ready"
            })
          end

        {category, riddles}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        ids = Enum.map(riddles, & &1.id)

        Repo.delete_all(
          from j in Oban.Job, where: fragment("(?->>'riddle_id')::int", j.args) in ^ids
        )

        Repo.delete_all(from r in Riddle, where: r.id in ^ids)
        Repo.delete!(category)
      end)
    end)

    %{riddles: riddles}
  end

  test "two riddles going live at once get different numbers", %{riddles: riddles} do
    results =
      riddles
      |> Enum.map(fn riddle ->
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn -> Games.transition(riddle.id, :live) end)
        end)
      end)
      |> Task.await_many()

    assert [{:ok, a}, {:ok, b}] = results
    assert Enum.sort([a.number, b.number]) == [1, 2]
  end

  test "the same riddle going live twice at once keeps one number", %{riddles: [riddle, _]} do
    results =
      for _ <- 1..2 do
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn -> Games.transition(riddle.id, :live) end)
        end)
      end
      |> Task.await_many()

    assert Enum.any?(results, &match?({:ok, %{number: 1}}, &1))
    assert {:invalid, "live", :live} in results
  end

  test "the unique index rejects a second riddle with the same number", %{riddles: [a, b]} do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.update_all(from(r in Riddle, where: r.id == ^a.id), set: [number: 1])

      assert_raise Postgrex.Error, ~r/riddles_number_index/, fn ->
        Repo.update_all(from(r in Riddle, where: r.id == ^b.id), set: [number: 1])
      end
    end)
  end
end
