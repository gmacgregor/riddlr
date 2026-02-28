defmodule Riddlr.Repo.Migrations.AddCategoryIdToRiddles do
  use Ecto.Migration

  def up do
    # Add category_id column
    alter table(:riddles) do
      add :category_id, references(:categories, on_delete: :nilify_all)
    end

    create index(:riddles, [:category_id])

    # Migrate existing category strings to category_id
    # Map riddles with matching category names to their category_id
    execute """
    UPDATE riddles r
    SET category_id = c.id
    FROM categories c
    WHERE LOWER(TRIM(r.category)) = LOWER(c.name)
    """

    # Set remaining riddles (with no match or null category) to "logic" (default)
    execute """
    UPDATE riddles r
    SET category_id = (SELECT id FROM categories WHERE name = 'logic')
    WHERE category_id IS NULL
    """

    # Make category_id required
    alter table(:riddles) do
      modify :category_id, :bigint, null: false
    end

    # Remove old category string column
    alter table(:riddles) do
      remove :category
    end
  end

  def down do
    # Restore category string column
    alter table(:riddles) do
      add :category, :string
    end

    # Migrate category_id back to category string
    execute """
    UPDATE riddles r
    SET category = c.name
    FROM categories c
    WHERE r.category_id = c.id
    """

    # Remove category_id and index
    drop index(:riddles, [:category_id])

    alter table(:riddles) do
      remove :category_id
    end
  end
end
