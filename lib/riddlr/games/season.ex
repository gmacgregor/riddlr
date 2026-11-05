defmodule Riddlr.Games.Season do
  @moduledoc """
  A named span of calendar days, start to end, both counted in the display
  time zone (see `Riddlr.DisplayTime`).

  A season is stored as two UTC instants: `starts_at`, midnight on its first
  day, and `ends_at`, midnight after its last day. `ends_at` is not part of
  the season. Admins work with days, `starts_on` and `ends_on`, which are
  virtual fields worked out from the instants.

  Seasons never overlap. A season's status (upcoming, current or past) comes
  from the clock and is never stored.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Riddlr.DisplayTime

  @type t :: %__MODULE__{}

  @typedoc "Where a season sits relative to an instant."
  @type status :: :upcoming | :current | :past

  @typedoc "A day field an admin edits."
  @type day_field :: :starts_on | :ends_on

  schema "seasons" do
    field :name, :string
    field :description, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime

    # First and last day in the display time zone. Filled by with_days/1.
    field :starts_on, :date, virtual: true
    field :ends_on, :date, virtual: true

    # Stays 0 until riddles carry a season (#121).
    field :riddle_count, :integer, virtual: true, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Fills `starts_on` and `ends_on` from the stored instants. A season with no
  instants yet is returned as it is.
  """
  @spec with_days(t()) :: t()
  def with_days(
        %__MODULE__{starts_at: %DateTime{} = starts_at, ends_at: %DateTime{} = ends_at} = season
      ) do
    %{
      season
      | starts_on: DisplayTime.to_date(starts_at),
        ends_on: ends_at |> DisplayTime.to_date() |> Date.add(-1)
    }
  end

  def with_days(%__MODULE__{} = season), do: season

  @doc """
  The season's status at `now`: upcoming before `starts_at`, past from
  `ends_at` on, current in between.
  """
  @spec status(t(), DateTime.t()) :: status()
  def status(%__MODULE__{starts_at: starts_at, ends_at: ends_at}, now) do
    cond do
      DateTime.before?(now, starts_at) -> :upcoming
      DateTime.before?(now, ends_at) -> :current
      true -> :past
    end
  end

  @doc """
  The day fields an edit may not change at `now`. A past season's days are
  locked, so its riddles and Standings stay put. The current season's first
  day is locked, so Standings already under way keep their start.
  """
  @spec locked_dates(t(), DateTime.t()) :: [day_field()]
  def locked_dates(%__MODULE__{id: nil}, _now), do: []

  def locked_dates(%__MODULE__{} = season, now) do
    case status(season, now) do
      :past -> [:starts_on, :ends_on]
      :current -> [:starts_on]
      :upcoming -> []
    end
  end

  @doc """
  Casts and checks a season's fields. Admins send days (`starts_on`,
  `ends_on`); the changeset turns them into the stored instants. `now`
  decides which days are locked; see `locked_dates/2`.
  """
  @spec changeset(t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def changeset(season, attrs, now) do
    season = with_days(season)

    season
    |> cast(attrs, [:name, :description, :starts_on, :ends_on])
    |> validate_required([:name, :starts_on, :ends_on])
    |> validate_unlocked(locked_dates(season, now))
    |> validate_length(:name, min: 2, max: 50)
    |> validate_length(:description, max: 500)
    |> unique_constraint(:name)
    |> validate_day_order()
    |> put_instants()
    |> check_constraint(:ends_on,
      name: :seasons_ends_at_after_starts_at,
      message: "must be on or after the start date"
    )
    |> exclusion_constraint(:ends_on,
      name: :seasons_no_overlap,
      message: "overlaps another season"
    )
  end

  @spec validate_unlocked(Ecto.Changeset.t(), [day_field()]) :: Ecto.Changeset.t()
  defp validate_unlocked(changeset, locked) do
    Enum.reduce(locked, changeset, fn field, changeset ->
      if changed?(changeset, field),
        do: add_error(changeset, field, "can't change now the season has started"),
        else: changeset
    end)
  end

  @spec validate_day_order(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_day_order(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.before?(ends_on, starts_on) do
      add_error(changeset, :ends_on, "must be on or after the start date")
    else
      changeset
    end
  end

  # The end instant is midnight after the last day, so a one-day season
  # still spans a whole day.
  @spec put_instants(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp put_instants(%Ecto.Changeset{valid?: true} = changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    changeset
    |> put_change(:starts_at, DisplayTime.day_start(starts_on))
    |> put_change(:ends_at, ends_on |> Date.add(1) |> DisplayTime.day_start())
  end

  defp put_instants(changeset), do: changeset
end
