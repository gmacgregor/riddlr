defmodule Riddlr.Repo.Migrations.AddPlayerStatsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :account_status, :string, default: "active", null: false
      add :total_points, :integer, default: 0, null: false
      add :wins_count, :integer, default: 0, null: false
      add :podium_count, :integer, default: 0, null: false
    end

    create index(:users, [:total_points])
    create index(:users, [:account_status])
  end
end
