defmodule Riddlr.Repo.Migrations.AddUserIdIndexToSolves do
  use Ecto.Migration

  # Standings group solves by player. The unique index on
  # [:riddle_id, :user_id] leads with riddle_id, so it can't serve that.
  def change do
    create_if_not_exists index(:solves, [:user_id])
  end
end
