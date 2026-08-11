defmodule Riddlr.Repo.Migrations.DropLiveUntilSolvedFromRiddles do
  use Ecto.Migration

  # Every riddle has a solve_time, and solve_time is what ends a round. The flag
  # was an escape hatch out of that rule — never exposed on the admin form, so
  # never set on a real riddle.
  def change do
    alter table(:riddles) do
      remove :live_until_solved, :boolean, default: false, null: false
    end
  end
end
