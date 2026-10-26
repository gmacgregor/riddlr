defmodule Riddlr.Repo.Migrations.AddNumberSequenceToRiddles do
  use Ecto.Migration

  # A riddle gets its "No. N" when it is inserted, so promo can use the number
  # before the riddle goes live. Numbers need not follow play order or be free
  # of gaps. Rows that exist now keep whatever number they have (often nil):
  # there is no back-fill.
  def up do
    execute "CREATE SEQUENCE riddles_number_seq OWNED BY riddles.number"

    # Start after any number already handed out at go-live, so the unique
    # index never rejects a new row.
    execute "SELECT setval('riddles_number_seq', COALESCE(MAX(number), 0) + 1, false) FROM riddles"

    execute "ALTER TABLE riddles ALTER COLUMN number SET DEFAULT nextval('riddles_number_seq')"
  end

  def down do
    execute "ALTER TABLE riddles ALTER COLUMN number DROP DEFAULT"
    execute "DROP SEQUENCE riddles_number_seq"
  end
end
