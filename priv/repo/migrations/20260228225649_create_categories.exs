defmodule Riddlr.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:name])

    # Seed initial categories
    execute(
      """
      INSERT INTO categories (name, inserted_at, updated_at)
      VALUES
        ('Logic', NOW(), NOW()),
        ('Trick Question', NOW(), NOW()),
        ('Wordplay', NOW(), NOW()),
        ('What am I', NOW(), NOW())
      """,
      "DELETE FROM categories WHERE name IN ('Logic', 'Trick Question', 'Wordplay', 'What am I')"
    )
  end
end
