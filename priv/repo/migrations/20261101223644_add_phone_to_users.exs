defmodule Riddlr.Repo.Migrations.AddPhoneToUsers do
  use Ecto.Migration

  def change do
    # Only confirmed numbers land here. See docs/adr/0002-phone-storage.md.
    alter table(:users) do
      add :phone, :binary
      add :phone_hash, :binary
      add :phone_confirmed_at, :utc_datetime
    end

    create unique_index(:users, [:phone_hash])

    # One row per code sent. Holds a pending number until it is confirmed or
    # its code expires; the hash stays a day for the per-number send limit.
    create table(:phone_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :phone, :binary
      add :phone_hash, :binary
      add :code_hash, :binary
      add :attempts, :integer, null: false, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:phone_codes, [:user_id, :inserted_at])
    create index(:phone_codes, [:phone_hash, :inserted_at])
    create index(:phone_codes, [:inserted_at])
  end
end
