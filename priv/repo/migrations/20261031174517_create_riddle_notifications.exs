defmodule Riddlr.Repo.Migrations.CreateRiddleNotifications do
  use Ecto.Migration

  # One row per Notification: a riddle, a player and a channel. The unique
  # index is what stops a second email when a fan-out runs twice. Rows go with
  # their riddle or player.
  def change do
    create table(:riddle_notifications) do
      add :riddle_id, references(:riddles, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:riddle_notifications, [:riddle_id, :user_id, :channel])
    create index(:riddle_notifications, [:user_id])
  end
end
