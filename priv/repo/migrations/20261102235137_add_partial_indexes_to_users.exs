defmodule Riddlr.Repo.Migrations.AddPartialIndexesToUsers do
  use Ecto.Migration

  # Each index holds only the rows its query wants. account_status stays out
  # of the predicates: the queries bind it as a parameter, and a generic plan
  # cannot match a parameter against an index predicate.
  def change do
    # Notification fan-out, by channel: opted-in, confirmed players with a
    # given lead time.
    create index(:users, [:notification_lead_time],
             name: :users_email_notify_lead_time_index,
             where: "notify_email = true AND confirmed_at IS NOT NULL"
           )

    create index(:users, [:notification_lead_time],
             name: :users_sms_notify_lead_time_index,
             where: "notify_sms = true AND phone_confirmed_at IS NOT NULL"
           )

    # The hourly prune of sign-up numbers older than a day.
    create index(:users, [:inserted_at],
             name: :users_signup_phone_inserted_at_index,
             where: "signup_phone IS NOT NULL"
           )
  end
end
