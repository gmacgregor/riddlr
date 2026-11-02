defmodule Riddlr.Repo.Migrations.AddTextRequestedToUsers do
  use Ecto.Migration

  def change do
    # Ticked Text at sign-up: text a code at the first log-in. The held
    # number is encrypted and wiped at that log-in or after a day. See
    # docs/adr/0002-phone-storage.md.
    alter table(:users) do
      add :text_requested, :boolean, default: false, null: false
      add :signup_phone, :binary
    end
  end
end
