defmodule Riddlr.Repo.Migrations.AddSeasonIdToRiddles do
  use Ecto.Migration

  # Every riddle belongs to one season. There is no production data, so no
  # backfill: a database that already holds riddles must be reset.
  def change do
    alter table(:riddles) do
      add :season_id, references(:seasons, on_delete: :restrict), null: false
    end

    create index(:riddles, [:season_id])
  end
end
