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

alias Riddlr.Games

riddles = [
  %{
    name: "The Keyboard",
    description:
      "What has keys but no locks, space but no room, and you can enter but can't go inside?",
    answers: ["keyboard", "a keyboard", "computer keyboard"],
    solve_time: 60,
    category: "technology",
    difficulty: "easy",
    hint: "Think about something you use every day to type.",
    hint_delay: 30,
    publish_status: "published"
  },
  %{
    name: "The Echo",
    description: "What can you hear but not see or touch, even though you control it?",
    answers: ["echo", "an echo"],
    solve_time: 90,
    category: "nature",
    difficulty: "medium",
    hint: "It's something that bounces back to you.",
    hint_delay: 45,
    publish_status: "published"
  },
  %{
    name: "The Light Switch",
    description:
      "I have cities, but no houses. I have mountains, but no trees. I have water, but no fish. What am I?",
    answers: ["map", "a map"],
    solve_time: 120,
    category: "logic",
    difficulty: "medium",
    hint: "Think about representation, not reality.",
    hint_delay: 60,
    publish_status: "published"
  },
  %{
    name: "The River",
    description:
      "What runs but never walks, has a mouth but never talks, has a bed but never sleeps?",
    answers: ["river", "a river", "stream"],
    solve_time: 90,
    category: "nature",
    difficulty: "easy",
    hint: "It flows through the land.",
    hint_delay: 45,
    publish_status: "published"
  },
  %{
    name: "The Future",
    description: "The more you take, the more you leave behind. What am I?",
    answers: ["footsteps", "steps", "footprints"],
    solve_time: 120,
    category: "logic",
    difficulty: "hard",
    hint: "Think about what you create as you move.",
    hint_delay: 60,
    publish_status: "published"
  },
  %{
    name: "Draft Riddle",
    description: "This riddle is not yet ready for play.",
    answers: ["test"],
    solve_time: 60,
    category: "test",
    difficulty: "easy",
    publish_status: "draft"
  }
]

Enum.each(riddles, fn riddle_attrs ->
  case Games.create_riddle(riddle_attrs) do
    {:ok, riddle} ->
      IO.puts("Created riddle: #{riddle.name}")

    {:error, changeset} ->
      IO.puts("Failed to create riddle: #{riddle_attrs.name}")
      IO.inspect(changeset.errors)
  end
end)

IO.puts("\nSeeded #{length(riddles)} riddles successfully!")
