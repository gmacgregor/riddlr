defmodule Riddlr.Repo.Migrations.AddNumberToRiddles do
  use Ecto.Migration

  # The public "No. N" of a riddle. `Games.transition/3` sets it when the
  # riddle goes live. Riddles that went live before this column existed keep
  # nil: there is no back-fill.
  def change do
    alter table(:riddles) do
      add :number, :integer
    end

    create unique_index(:riddles, [:number])
  end
end
