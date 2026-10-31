defmodule Riddlr.Repo.Migrations.CreatePracticeRiddles do
  use Ecto.Migration

  def change do
    create table(:practice_riddles) do
      add :description, :text, null: false
      add :answer, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
