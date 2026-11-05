defmodule Riddlr.Repo.Migrations.CreateSeasons do
  use Ecto.Migration

  def change do
    create table(:seasons) do
      # citext makes the unique index ignore case, as usernames do.
      add :name, :citext, null: false
      add :description, :text
      # Midnight in the display time zone on the first day, and midnight after
      # the last day, both in UTC. The end is not part of the season.
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:seasons, [:name])

    create constraint(:seasons, :seasons_ends_at_after_starts_at, check: "ends_at > starts_at")

    # Half-open ranges ('[)'): back-to-back seasons share an end and a start
    # instant but no time, so they do not clash.
    create constraint(:seasons, :seasons_no_overlap,
             exclude: ~s|gist (tsrange(starts_at, ends_at, '[)') WITH &&)|
           )
  end
end
