defmodule Riddlr.Repo.Migrations.AddReadyBeforeSecondsToRiddles do
  use Ecto.Migration

  def change do
    alter table(:riddles) do
      add :ready_before_seconds, :integer, default: 600, null: false
    end
  end
end
