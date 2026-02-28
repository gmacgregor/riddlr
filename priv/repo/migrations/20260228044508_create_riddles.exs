defmodule Riddlr.Repo.Migrations.CreateRiddles do
  use Ecto.Migration

  def change do
    create table(:riddles) do
      add :name, :string, null: false
      add :description, :text, null: false
      add :answers, {:array, :string}, null: false, default: []
      add :play_status, :string, null: false, default: "closed"
      add :solve_time, :integer, null: false
      add :category, :string
      add :difficulty, :string
      add :hint, :text
      add :hint_delay, :integer
      add :live_date, :utc_datetime
      add :publish_status, :string, null: false, default: "draft"
      add :first_solver_id, references(:users, on_delete: :nilify_all)
      add :first_solve_time, :integer
      add :completion_rate, :float
      add :average_solve_time, :float

      timestamps(type: :utc_datetime)
    end

    create index(:riddles, [:play_status])
    create index(:riddles, [:live_date])
    create index(:riddles, [:category])
    create index(:riddles, [:first_solver_id])
  end
end
