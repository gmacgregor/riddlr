defmodule Riddlr.Repo.Migrations.RenameArchiveCooldownToArchiveAfterSeconds do
  use Ecto.Migration

  def up do
    rename table(:riddles), :archive_cooldown_minutes, to: :archive_after_seconds
    execute "ALTER TABLE riddles ALTER COLUMN archive_after_seconds SET DEFAULT 180"
    execute "UPDATE riddles SET archive_after_seconds = archive_after_seconds * 60"
  end

  def down do
    execute "UPDATE riddles SET archive_after_seconds = archive_after_seconds / 60"
    execute "ALTER TABLE riddles ALTER COLUMN archive_after_seconds SET DEFAULT 3"
    rename table(:riddles), :archive_after_seconds, to: :archive_cooldown_minutes
  end
end
