defmodule Riddlr.Repo.Migrations.DropStatCountersFromUsers do
  use Ecto.Migration

  # Player stats come from `solves` now (see Riddlr.Standings). These
  # counters were only ever written, never read. Dropping total_points
  # drops its index too, so `down/0` puts that back as well.
  def up do
    alter table(:users) do
      remove :total_points
      remove :wins_count
      remove :podium_count
    end
  end

  def down do
    alter table(:users) do
      add :total_points, :integer, default: 0, null: false
      add :wins_count, :integer, default: 0, null: false
      add :podium_count, :integer, default: 0, null: false
    end

    create index(:users, [:total_points])
  end
end
