defmodule Riddlr.Repo.Migrations.CreateSolves do
  use Ecto.Migration

  # One row per correct solver, written when the riddle completes so the board
  # outlives the ETS rows that archive drops. A deleted user leaves their row
  # with a nil `user_id`, so the board keeps every place.
  def change do
    create table(:solves) do
      add :riddle_id, references(:riddles, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :placement, :integer, null: false
      add :points, :integer, null: false
      add :solve_time_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:solves, [:riddle_id, :user_id])
    create unique_index(:solves, [:riddle_id, :placement])
  end
end
