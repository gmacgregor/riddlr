defmodule Riddlr.Repo.Migrations.AddArchiveCooldownToRiddles do
  use Ecto.Migration

  def change do
    alter table(:riddles) do
      add :archive_cooldown_minutes, :integer, default: 3, null: false
    end
  end
end
