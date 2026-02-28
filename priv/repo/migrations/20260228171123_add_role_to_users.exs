defmodule Riddlr.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    create_query =
      "CREATE TYPE user_role AS ENUM ('super_admin', 'moderator', 'editor', 'viewer', 'player')"

    drop_query = "DROP TYPE user_role"
    execute(create_query, drop_query)

    alter table(:users) do
      add :role, :user_role, default: "player", null: false
    end

    create index(:users, [:role])
  end
end
