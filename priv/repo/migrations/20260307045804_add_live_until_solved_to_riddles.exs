defmodule Riddlr.Repo.Migrations.AddLiveUntilSolvedToRiddles do
  use Ecto.Migration

  def change do
    alter table(:riddles) do
      add :live_until_solved, :boolean, default: false, null: false
    end
  end
end
