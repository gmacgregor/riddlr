defmodule Riddlr.GamesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Riddlr.Games` context.
  """

  def unique_riddle_name, do: "Riddle #{System.unique_integer([:positive])}"

  def riddle_fixture(attrs \\ %{}) do
    # Ensure a default category exists for tests
    category_id = Map.get(attrs, :category_id) || get_or_create_default_category()

    {:ok, riddle} =
      attrs
      |> Enum.into(%{
        name: unique_riddle_name(),
        description: "What has keys but no locks, space but no room?",
        answers: ["keyboard", "a keyboard"],
        solve_time: 60,
        category_id: category_id,
        difficulty: "easy"
      })
      |> Riddlr.Games.create_riddle()

    # Reload with category preloaded to match Games.get_riddle! and Games.list_riddles
    Riddlr.Games.get_riddle!(riddle.id)
  end

  defp get_or_create_default_category do
    case Riddlr.Repo.get_by(Riddlr.Games.Category, name: "logic") do
      nil ->
        {:ok, category} = Riddlr.Games.create_category(%{name: "logic"})
        category.id
      category ->
        category.id
    end
  end
end
