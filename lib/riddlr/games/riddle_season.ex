defmodule Riddlr.Games.RiddleSeason do
  @moduledoc """
  Keeps a riddle's Season in step with its Live date when the riddle is
  saved, and refuses saves that break the Season rules.
  `Riddlr.Games.Schedule.save/2` runs `resolve/2` on the riddle changeset
  before it decides what the save does.

  A save picks the riddle's Season in this order:

    1. If the save changes the Season, keep it.
    2. Otherwise, if the save changes the Live date and the new Live date
       falls in a current or upcoming Season, use that Season. It may
       already be the riddle's Season.
    3. Otherwise, keep the Season the riddle has.

  Then it checks the result:

    * A Season the save sets must be current or upcoming. A riddle already
      in a past Season keeps it and can't change it.
    * A riddle that will be published after the save must have its Live date
      inside its Season. Only a save that publishes the riddle, or changes
      its Live date or Season, is checked.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Riddlr.Games.Season
  alias Riddlr.Repo

  @doc """
  Picks the riddle's Season for the save at `now` and checks it. The checks
  run on an invalid changeset too, so the editor sees every error at once.
  """
  @spec resolve(Ecto.Changeset.t(), DateTime.t()) :: Ecto.Changeset.t()
  def resolve(%Ecto.Changeset{} = changeset, now) do
    changeset
    |> validate_picked_season(now)
    |> follow_live_date(now)
    |> validate_live_date_in_season()
  end

  # A Season the save sets outright must be current or upcoming, and a riddle
  # in a past Season stays there.
  @spec validate_picked_season(Ecto.Changeset.t(), DateTime.t()) :: Ecto.Changeset.t()
  defp validate_picked_season(changeset, now) do
    case fetch_change(changeset, :season_id) do
      {:ok, season_id} ->
        cond do
          past = past_season(stored_season_id(changeset), now) ->
            add_error(changeset, :season_id, "can't change: %{season} is a past season",
              season: past.name
            )

          past_season(season_id, now) ->
            add_error(changeset, :season_id, "is a past season; pick a current or upcoming one")

          true ->
            changeset
        end

      :error ->
        changeset
    end
  end

  # The Season the riddle is in before the save; nil for a new riddle. Read
  # from `data`, not `get_field/2`, which would return the Season this save
  # sets.
  @spec stored_season_id(Ecto.Changeset.t()) :: integer() | nil
  defp stored_season_id(changeset), do: changeset.data.season_id

  # The Season with `season_id`, if it is past at `now`.
  @spec past_season(integer() | nil, DateTime.t()) :: Season.t() | nil
  defp past_season(season_id, now) do
    case get_season(season_id) do
      %Season{} = season -> if Season.status(season, now) == :past, do: season
      nil -> nil
    end
  end

  # A missing `season_id` is left to the riddle changeset's required check.
  @spec get_season(integer() | nil) :: Season.t() | nil
  defp get_season(nil), do: nil
  defp get_season(season_id), do: Repo.get(Season, season_id)

  # A riddle in a past Season can't follow its Live date out of it.
  @spec follow_live_date(Ecto.Changeset.t(), DateTime.t()) :: Ecto.Changeset.t()
  defp follow_live_date(changeset, now) do
    with false <- changed?(changeset, :season_id),
         %DateTime{} = live_date <- get_change(changeset, :live_date),
         %Season{id: season_id} <- open_season_holding(live_date, now) do
      case past_season(stored_season_id(changeset), now) do
        nil ->
          put_change(changeset, :season_id, season_id)

        past ->
          add_error(
            changeset,
            :live_date,
            "would move this riddle out of %{season}, a past season",
            season: past.name
          )
      end
    else
      _ -> changeset
    end
  end

  # A riddle that will be published after the save must go live inside its
  # Season. Only a save that publishes the riddle, or moves its Live date or
  # Season, is checked, so other edits to a published riddle still save.
  @spec validate_live_date_in_season(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_live_date_in_season(changeset) do
    live_date = get_field(changeset, :live_date)

    with true <- get_field(changeset, :publish_status) == "published",
         %DateTime{} <- live_date,
         true <- Enum.any?([:publish_status, :live_date, :season_id], &changed?(changeset, &1)),
         %Season{} = season <- get_season(get_field(changeset, :season_id)),
         false <- Season.holds?(season, live_date) do
      season = Season.with_days(season)

      add_error(changeset, :live_date, "must fall within %{season} (%{starts_on} to %{ends_on})",
        season: season.name,
        starts_on: Date.to_iso8601(season.starts_on),
        ends_on: Date.to_iso8601(season.ends_on)
      )
    else
      _ -> changeset
    end
  end

  # The current or upcoming Season that holds `instant`, if any.
  @spec open_season_holding(DateTime.t(), DateTime.t()) :: Season.t() | nil
  defp open_season_holding(instant, now) do
    Season
    |> where([s], s.starts_at <= ^instant and s.ends_at > ^instant)
    |> where([s], s.ends_at > ^now)
    |> Repo.one()
  end
end
