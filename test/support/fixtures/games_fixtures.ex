defmodule Riddlr.GamesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Riddlr.Games` context.
  """

  @doc """
  Generate a riddle.
  """
  def riddle_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        answers: ["option1", "option2"],
        average_solve_time: 120.5,
        category: "some category",
        completion_rate: 120.5,
        description: "some description",
        difficulty: "some difficulty",
        first_solve_time: 42,
        hint: "some hint",
        hint_delay: 42,
        live_date: ~U[2026-02-27 04:45:00Z],
        name: "some name",
        play_status: "some play_status",
        publish_status: "some publish_status",
        solve_time: 42
      })

    {:ok, riddle} = Riddlr.Games.create_riddle(scope, attrs)
    riddle
  end
end
