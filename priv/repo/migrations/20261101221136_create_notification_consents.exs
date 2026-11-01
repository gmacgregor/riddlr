defmodule Riddlr.Repo.Migrations.CreateNotificationConsents do
  use Ecto.Migration

  # Proof of notification consent (CASL): one row each time a player turns a
  # channel on or off. Rows are only ever added. They go with their player.
  def change do
    create table(:notification_consents) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :action, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notification_consents, [:user_id])
  end
end
