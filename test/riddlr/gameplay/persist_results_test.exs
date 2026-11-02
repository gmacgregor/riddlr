defmodule Riddlr.Gameplay.PersistResultsTest do
  use Riddlr.DataCase, async: true

  alias Ecto.Multi
  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.{Entry, Solve}
  alias Riddlr.{AccountsFixtures, GamesFixtures}

  setup do
    riddle =
      GamesFixtures.riddle_fixture(%{publish_status: "published"})
      |> Ecto.Changeset.change(play_status: "live")
      |> Repo.update!()

    for _ <- 1..5, do: {:correct, _, _} = guess(riddle, "keyboard")
    for _ <- 1..2, do: :incorrect = guess(riddle, "mouse")

    stats = %{solves: Gameplay.solve_rows(riddle.id), entries: Gameplay.entry_rows(riddle.id)}

    %{riddle: riddle, stats: stats}
  end

  describe "persist_results/3" do
    test "saves every solve and entry across chunks", %{riddle: riddle, stats: stats} do
      assert {:ok, _changes} =
               Multi.new()
               |> Gameplay.persist_results(stats, chunk_size: 2)
               |> Repo.transaction()

      assert saved(Solve, riddle.id) |> Enum.map(& &1.placement) |> Enum.sort() == [1, 2, 3, 4, 5]
      assert length(saved(Entry, riddle.id)) == 7
    end

    test "running it twice saves each row once", %{riddle: riddle, stats: stats} do
      for _ <- 1..2 do
        assert {:ok, _changes} =
                 Multi.new()
                 |> Gameplay.persist_results(stats, chunk_size: 2)
                 |> Repo.transaction()
      end

      assert length(saved(Solve, riddle.id)) == 5
      assert length(saved(Entry, riddle.id)) == 7
    end

    test "adds no steps when nobody guessed" do
      assert Gameplay.persist_results(Multi.new(), %{solves: [], entries: []}) |> Multi.to_list() ==
               []

      assert Gameplay.persist_results(Multi.new(), %{}) |> Multi.to_list() == []
    end
  end

  defp guess(riddle, text) do
    Gameplay.submit_answer(riddle, AccountsFixtures.user_fixture(), text)
  end

  defp saved(schema, riddle_id) do
    Repo.all(from r in schema, where: r.riddle_id == ^riddle_id)
  end
end
