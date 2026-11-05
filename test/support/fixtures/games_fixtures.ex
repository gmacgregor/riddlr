defmodule Riddlr.GamesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Riddlr.Games` context.
  """

  @doc "The scope seeds and fixtures write with: it holds every permission."
  def system_scope, do: Riddlr.Accounts.Scope.for_system()

  def unique_riddle_name, do: "Riddle #{System.unique_integer([:positive])}"

  def riddle_fixture(attrs \\ %{}) do
    # Ensure a default category exists for tests
    category_id = Map.get(attrs, :category_id) || get_or_create_default_category()
    season_id = Map.get(attrs, :season_id) || get_or_create_default_season()

    {:ok, riddle} =
      attrs
      |> Enum.into(%{
        name: unique_riddle_name(),
        description: "What has keys but no locks, space but no room?",
        answers: ["keyboard", "a keyboard"],
        solve_time: 60,
        category_id: category_id,
        season_id: season_id,
        difficulty: "easy"
      })
      |> then(&Riddlr.Games.create_riddle(system_scope(), &1))

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

    {:ok, scheduled} =
      Riddlr.Games.save_riddle(system_scope(), riddle, %{"live_date" => live_date})

    scheduled
  end

  @doc """
  A saved solve of `riddle` by `user`. Pass `:placement`, `:points` and
  `:solve_time_ms` to override the defaults (1st, 10 points, 3s).
  """
  def solve_fixture(riddle, user, attrs \\ %{}) do
    Riddlr.Repo.insert!(
      struct!(
        Riddlr.Gameplay.Solve,
        Map.merge(
          %{placement: 1, points: 10, solve_time_ms: 3_000},
          Map.merge(attrs, %{riddle_id: riddle.id, user_id: user.id})
        )
      )
    )
  end

  @doc "A saved entry: `user` guessed on `riddle`."
  def entry_fixture(riddle, user) do
    Riddlr.Repo.insert!(%Riddlr.Gameplay.Entry{riddle_id: riddle.id, user_id: user.id})
  end

  @doc """
  A saved season with a unique name. Its dates default to a one-month span
  far in the future, so it never clashes with today. Pass `:starts_on` and
  `:ends_on` to place it, and keep seasons in one test from overlapping.
  """
  def season_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])
    # 31-day spans 32 days apart: distinct fixtures never overlap.
    starts_on = Date.add(~D[2100-01-01], rem(n, 10_000) * 32)

    {:ok, season} =
      attrs
      |> Enum.into(%{
        name: "Season #{n}",
        starts_on: starts_on,
        ends_on: Date.add(starts_on, 30)
      })
      |> then(&Riddlr.Games.create_season(system_scope(), &1))

    season
  end

  @doc """
  The shared "logic" category every riddle fixture hangs off.
  """
  def category_fixture do
    Riddlr.Repo.get!(Riddlr.Games.Category, get_or_create_default_category())
  end

  @doc """
  The shared season every riddle fixture belongs to unless given
  `:season_id`. It runs from 2000 to 2099, so any Live date a test picks
  falls inside it. A test that creates its own seasons in that span must give
  its riddles one of them, or the default season will clash with it.
  """
  def default_season_fixture do
    Riddlr.Games.get_season!(get_or_create_default_season())
  end

  defp get_or_create_default_season do
    case Riddlr.Repo.get_by(Riddlr.Games.Season, name: "Default season") do
      nil ->
        {:ok, season} =
          Riddlr.Games.create_season(system_scope(), %{
            name: "Default season",
            starts_on: ~D[2000-01-01],
            ends_on: ~D[2099-12-31]
          })

        season.id

      season ->
        season.id
    end
  end

  defp get_or_create_default_category do
    case Riddlr.Repo.get_by(Riddlr.Games.Category, name: "logic") do
      nil ->
        {:ok, category} = Riddlr.Games.create_category(system_scope(), %{name: "logic"})
        category.id

      category ->
        category.id
    end
  end
end
