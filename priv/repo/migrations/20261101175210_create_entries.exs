defmodule Riddlr.Repo.Migrations.CreateEntries do
  use Ecto.Migration

  # One row per player who guessed a riddle, written when it completes, so
  # Standings can show solve rate. A deleted user leaves their row with a nil
  # `user_id`, like `solves`.
  def change do
    create table(:entries) do
      add :riddle_id, references(:riddles, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:entries, [:riddle_id, :user_id])
    create index(:entries, [:user_id])
  end
end
