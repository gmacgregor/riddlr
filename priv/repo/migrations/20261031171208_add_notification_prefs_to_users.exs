defmodule Riddlr.Repo.Migrations.AddNotificationPrefsToUsers do
  use Ecto.Migration

  # All three fields land now so later notification slices need no user
  # migration. `notify_sms` stays unused until SMS ships.
  def change do
    alter table(:users) do
      add :notify_email, :boolean, null: false, default: false
      add :notify_sms, :boolean, null: false, default: false
      add :notification_lead_time, :string, null: false, default: "lobby_open"
    end
  end
end
