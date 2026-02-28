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
        ('logic', NOW(), NOW()),
        ('trick question', NOW(), NOW()),
        ('wordplay/pun', NOW(), NOW()),
        ('what am i', NOW(), NOW())
      """,
      "DELETE FROM categories WHERE name IN ('logic', 'trick question', 'wordplay/pun', 'what am i')"
    )
  end
end
