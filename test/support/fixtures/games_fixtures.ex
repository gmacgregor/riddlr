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

  @doc """
  A published riddle already in `scheduled` state, with its ready/live jobs
  enqueued. Pass `:live_date` to control when it goes live.
  """
  def scheduled_riddle_fixture(attrs \\ %{}) do
    {live_date, attrs} =
      Map.pop_lazy(attrs, :live_date, fn ->
        DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      end)

    riddle = riddle_fixture(Map.put(attrs, :publish_status, "published"))

    {:ok, scheduled} = Riddlr.Games.save_riddle(riddle, %{"live_date" => live_date})
    scheduled
  end

  @doc """
  The shared "logic" category every riddle fixture hangs off.
  """
  def category_fixture do
    Riddlr.Repo.get!(Riddlr.Games.Category, get_or_create_default_category())
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
