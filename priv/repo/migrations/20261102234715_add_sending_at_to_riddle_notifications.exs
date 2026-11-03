defmodule Riddlr.Repo.Migrations.AddSendingAtToRiddleNotifications do
  use Ecto.Migration

  # When a send job claimed the row. A claim older than a few minutes belongs
  # to a job that died, and another job may take it over.
  def change do
    alter table(:riddle_notifications) do
      add :sending_at, :utc_datetime
    end
  end
end
