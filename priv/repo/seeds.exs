# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Riddlr.Repo.insert!(%Riddlr.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Riddlr.Accounts
alias Riddlr.Accounts.Scope
alias Riddlr.Games
alias Riddlr.Repo

# Create admin and player users for testing
# Note: We register first, then update role directly via Repo
# This is required because role cannot be cast in registration_changeset (security)
IO.puts("Creating test users...")

case Accounts.register_user(%{email: "admin@example.com", username: "admin"}) do
  {:ok, admin} ->
    # Update role directly via repo (only in seeds)
    _admin = admin |> Ecto.Changeset.change(role: :super_admin) |> Repo.update!()
    IO.puts("✓ Created admin user: admin@example.com (role: super_admin)")
    IO.puts("  To log in, use the magic link sent to the Swoosh mailbox")
    IO.puts("  Visit: http://localhost:4000/dev/mailbox")

  {:error, changeset} ->
    IO.puts("✗ Failed to create admin user")
    IO.inspect(changeset.errors)
end

case Accounts.register_user(%{email: "editor@example.com", username: "editor"}) do
  {:ok, editor} ->
    editor |> Ecto.Changeset.change(role: :editor) |> Repo.update!()
    IO.puts("✓ Created editor user: editor@example.com (role: editor)")

  {:error, changeset} ->
    IO.puts("✗ Failed to create editor user")
    IO.inspect(changeset.errors)
end

case Accounts.register_user(%{email: "player@example.com", username: "player"}) do
  {:ok, _player} ->
    # Player uses default role, no update needed
    IO.puts("✓ Created player user: player@example.com (role: player)")

  {:error, changeset} ->
    IO.puts("✗ Failed to create player user")
    IO.inspect(changeset.errors)
end

IO.puts("\nSeeding a season...")

# Every riddle belongs to a season. Reuse a current or upcoming one, or make
# one that runs from today for three months. Starting today keeps it clear of
# any past season.
season =
  case Games.default_season(Games.list_current_and_upcoming_seasons(), nil) do
    nil ->
      starts_on = Riddlr.DisplayTime.to_date(Riddlr.Clock.utc_now())
      ends_on = starts_on |> Date.shift(month: 3) |> Date.add(-1)

      {:ok, season} =
        Games.create_season(Scope.for_system(), %{
          name: "Season of #{starts_on}",
          starts_on: starts_on,
          ends_on: ends_on
        })

      IO.puts("Created season: #{season.name} (#{season.starts_on} to #{season.ends_on})")
      season

    season ->
      IO.puts("Using season: #{season.name}")
      season
  end

IO.puts("\nSeeding riddles...")

{riddles, _binding} = Code.eval_file("riddles.exs", __DIR__)

# Look up each category by name, creating any that do not exist yet.
category_ids =
  riddles
  |> Enum.map(& &1.category)
  |> Enum.uniq()
  |> Map.new(fn name ->
    category =
      Repo.get_by(Games.Category, name: name) ||
        Repo.insert!(%Games.Category{name: name})

    {name, category.id}
  end)

riddles =
  Enum.map(riddles, fn %{category: name} = riddle ->
    riddle
    |> Map.delete(:category)
    |> Map.put(:category_id, category_ids[name])
    |> Map.put(:season_id, season.id)
  end)

Enum.each(riddles, fn riddle_attrs ->
  case Games.create_riddle(Scope.for_system(), riddle_attrs) do
    {:ok, riddle} ->
      IO.puts("Created riddle: #{riddle.name}")

    {:error, changeset} ->
      IO.puts("Failed to create riddle: #{riddle_attrs.name}")
      IO.inspect(changeset.errors)
  end
end)

IO.puts("\nSeeded #{length(riddles)} riddles successfully!")

IO.puts("\nSeeding practice riddles...")

# Shown on Home while nothing is scheduled. Added only to an empty table, so
# a second run does not double them.
practice_riddles = [
  %{description: "The more you take, the more you leave behind. What am I?", answer: "footsteps"},
  %{
    description: "I have keys but open no locks. I have space but no room. What am I?",
    answer: "keyboard"
  },
  %{description: "I speak without a mouth and hear without ears. What am I?", answer: "echo"},
  %{description: "What gets wetter the more it dries?", answer: "towel"},
  %{description: "What has hands but can’t clap?", answer: "clock"},
  %{description: "The more of me there is, the less you see. What am I?", answer: "darkness"}
]

if Games.count_practice_riddles() == 0 do
  Enum.each(practice_riddles, fn attrs ->
    {:ok, practice} = Games.create_practice_riddle(Scope.for_system(), attrs)
    IO.puts("Created practice riddle: #{practice.answer}")
  end)
else
  IO.puts("Practice riddles already exist, skipping.")
end
