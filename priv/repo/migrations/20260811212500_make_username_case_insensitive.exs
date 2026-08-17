defmodule Riddlr.Repo.Migrations.MakeUsernameCaseInsensitive do
  use Ecto.Migration

  # citext gives us case-insensitive uniqueness for free, the same way email
  # already works. Postgres rebuilds the unique index when the type changes,
  # so this fails loudly if two usernames differ only by case.
  def up do
    execute "ALTER TABLE users ALTER COLUMN username TYPE citext"
  end

  def down do
    execute "ALTER TABLE users ALTER COLUMN username TYPE varchar(255)"
  end
end
