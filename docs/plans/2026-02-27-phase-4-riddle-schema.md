# Phase 4: Riddle Schema & Contexts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create Games context with Riddle schema, Gameplay context stub, CRUD functions, and sample seeds.

**Architecture:** Games context owns Riddle schema with play_status state machine (closed/scheduled/ready/live/completed/archived). Gameplay context will handle ephemeral state in Phase 9. One-way dependency: Gameplay can call Games, not vice versa.

**Tech Stack:** Phoenix 1.8, Ecto 3.13, PostgreSQL, ExUnit

---

## Task 1: Create Games Context and Riddle Schema

**Files:**
- Create: `lib/riddlr/games.ex`
- Create: `lib/riddlr/games/riddle.ex`
- Create: `priv/repo/migrations/TIMESTAMP_create_riddles.exs`

**Step 1: Generate Games context with Riddle schema**

Run: `mix phx.gen.context Games Riddle riddles name:string description:text answers:array:string play_status:string solve_time:integer category:string difficulty:string hint:text hint_delay:integer live_date:utc_datetime publish_status:string first_solver_id:references:users first_solve_time:integer completion_rate:float average_solve_time:float`

Expected: Migration and context files generated

**Step 2: Update migration with constraints and indices**

In `priv/repo/migrations/*_create_riddles.exs`, modify the migration:

```elixir
defmodule Riddlr.Repo.Migrations.CreateRiddles do
  use Ecto.Migration

  def change do
    create table(:riddles) do
      add :name, :string, null: false
      add :description, :text, null: false
      add :answers, {:array, :string}, null: false, default: []
      add :play_status, :string, null: false, default: "closed"
      add :solve_time, :integer, null: false
      add :category, :string
      add :difficulty, :string
      add :hint, :text
      add :hint_delay, :integer
      add :live_date, :utc_datetime
      add :publish_status, :string, null: false, default: "draft"
      add :first_solver_id, references(:users, on_delete: :nilify_all)
      add :first_solve_time, :integer
      add :completion_rate, :float
      add :average_solve_time, :float

      timestamps(type: :utc_datetime)
    end

    create index(:riddles, [:play_status])
    create index(:riddles, [:live_date])
    create index(:riddles, [:category])
    create index(:riddles, [:first_solver_id])
  end
end
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration successful, riddles table created

**Step 4: Update Riddle schema with validations and enums**

In `lib/riddlr/games/riddle.ex`, replace generated schema:

```elixir
defmodule Riddlr.Games.Riddle do
  use Ecto.Schema
  import Ecto.Changeset

  @play_statuses ~w(closed scheduled ready live completed archived)
  @publish_statuses ~w(draft published)
  @difficulties ~w(easy medium hard expert)

  schema "riddles" do
    field :name, :string
    field :description, :string
    field :answers, {:array, :string}, default: []
    field :play_status, :string, default: "closed"
    field :solve_time, :integer
    field :category, :string
    field :difficulty, :string
    field :hint, :string
    field :hint_delay, :integer
    field :live_date, :utc_datetime
    field :publish_status, :string, default: "draft"
    field :first_solve_time, :integer
    field :completion_rate, :float
    field :average_solve_time, :float

    belongs_to :first_solver, Riddlr.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(riddle, attrs) do
    riddle
    |> cast(attrs, [
      :name,
      :description,
      :answers,
      :play_status,
      :solve_time,
      :category,
      :difficulty,
      :hint,
      :hint_delay,
      :live_date,
      :publish_status,
      :first_solver_id,
      :first_solve_time,
      :completion_rate,
      :average_solve_time
    ])
    |> validate_required([:name, :description, :answers, :solve_time])
    |> validate_answers()
    |> validate_inclusion(:play_status, @play_statuses)
    |> validate_inclusion(:publish_status, @publish_statuses)
    |> validate_inclusion(:difficulty, @difficulties, allow_nil: true)
    |> validate_number(:solve_time, greater_than: 0)
    |> validate_number(:hint_delay, greater_than_or_equal_to: 0)
    |> validate_number(:completion_rate, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
    |> validate_number(:average_solve_time, greater_than_or_equal_to: 0.0)
    |> foreign_key_constraint(:first_solver_id)
  end

  defp validate_answers(changeset) do
    changeset
    |> validate_length(:answers, min: 1, message: "must have at least one answer")
    |> validate_change(:answers, fn :answers, answers ->
      if Enum.all?(answers, &(is_binary(&1) && String.trim(&1) != "")) do
        []
      else
        [answers: "all answers must be non-empty strings"]
      end
    end)
  end

  def play_statuses, do: @play_statuses
  def publish_statuses, do: @publish_statuses
  def difficulties, do: @difficulties
end
```

**Step 5: Verify compilation**

Run: `mix compile`
Expected: Compiles successfully

**Step 6: Commit**

Run: `git add . && git commit -m "feat: add Games context with Riddle schema"`
Expected: Commit successful

---

## Task 2: Add CRUD Functions to Games Context

**Files:**
- Modify: `lib/riddlr/games.ex`
- Create: `test/riddlr/games_test.exs`

**Step 1: Write tests for CRUD functions**

Create `test/riddlr/games_test.exs`:

```elixir
defmodule Riddlr.GamesTest do
  use Riddlr.DataCase

  alias Riddlr.Games

  describe "riddles" do
    alias Riddlr.Games.Riddle

    import Riddlr.GamesFixtures

    @invalid_attrs %{name: nil, description: nil, answers: [], solve_time: nil}

    test "list_riddles/0 returns all riddles" do
      riddle = riddle_fixture()
      assert Games.list_riddles() == [riddle]
    end

    test "get_riddle!/1 returns the riddle with given id" do
      riddle = riddle_fixture()
      assert Games.get_riddle!(riddle.id) == riddle
    end

    test "create_riddle/1 with valid data creates a riddle" do
      valid_attrs = %{
        name: "Test Riddle",
        description: "A test riddle description",
        answers: ["answer1", "answer2"],
        solve_time: 60,
        category: "logic",
        difficulty: "medium"
      }

      assert {:ok, %Riddle{} = riddle} = Games.create_riddle(valid_attrs)
      assert riddle.name == "Test Riddle"
      assert riddle.description == "A test riddle description"
      assert riddle.answers == ["answer1", "answer2"]
      assert riddle.solve_time == 60
      assert riddle.play_status == "closed"
      assert riddle.publish_status == "draft"
    end

    test "create_riddle/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Games.create_riddle(@invalid_attrs)
    end

    test "create_riddle/1 requires at least one answer" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: [],
        solve_time: 60
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{answers: ["must have at least one answer"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates play_status enum" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        play_status: "invalid_status"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{play_status: ["is invalid"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates difficulty enum" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        difficulty: "impossible"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{difficulty: ["is invalid"]} = errors_on(changeset)
    end

    test "update_riddle/2 with valid data updates the riddle" do
      riddle = riddle_fixture()
      update_attrs = %{
        name: "Updated Name",
        description: "Updated description",
        answers: ["new_answer"],
        solve_time: 120
      }

      assert {:ok, %Riddle{} = riddle} = Games.update_riddle(riddle, update_attrs)
      assert riddle.name == "Updated Name"
      assert riddle.description == "Updated description"
      assert riddle.answers == ["new_answer"]
      assert riddle.solve_time == 120
    end

    test "update_riddle/2 with invalid data returns error changeset" do
      riddle = riddle_fixture()
      assert {:error, %Ecto.Changeset{}} = Games.update_riddle(riddle, @invalid_attrs)
      assert riddle == Games.get_riddle!(riddle.id)
    end

    test "delete_riddle/1 deletes the riddle" do
      riddle = riddle_fixture()
      assert {:ok, %Riddle{}} = Games.delete_riddle(riddle)
      assert_raise Ecto.NoResultsError, fn -> Games.get_riddle!(riddle.id) end
    end

    test "change_riddle/1 returns a riddle changeset" do
      riddle = riddle_fixture()
      assert %Ecto.Changeset{} = Games.change_riddle(riddle)
    end
  end
end
```

**Step 2: Create test fixtures**

Create `test/support/fixtures/games_fixtures.ex`:

```elixir
defmodule Riddlr.GamesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Riddlr.Games` context.
  """

  def unique_riddle_name, do: "Riddle #{System.unique_integer([:positive])}"

  def riddle_fixture(attrs \\ %{}) do
    {:ok, riddle} =
      attrs
      |> Enum.into(%{
        name: unique_riddle_name(),
        description: "What has keys but no locks, space but no room?",
        answers: ["keyboard", "a keyboard"],
        solve_time: 60,
        category: "logic",
        difficulty: "easy"
      })
      |> Riddlr.Games.create_riddle()

    riddle
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `mix test test/riddlr/games_test.exs`
Expected: FAIL - Games context functions not implemented

**Step 4: Update Games context with CRUD functions**

In `lib/riddlr/games.ex`, replace the generated content:

```elixir
defmodule Riddlr.Games do
  @moduledoc """
  The Games context.
  """

  import Ecto.Query, warn: false
  alias Riddlr.Repo

  alias Riddlr.Games.Riddle

  @doc """
  Returns the list of riddles.

  ## Examples

      iex> list_riddles()
      [%Riddle{}, ...]

  """
  def list_riddles do
    Repo.all(Riddle)
  end

  @doc """
  Gets a single riddle.

  Raises `Ecto.NoResultsError` if the Riddle does not exist.

  ## Examples

      iex> get_riddle!(123)
      %Riddle{}

      iex> get_riddle!(456)
      ** (Ecto.NoResultsError)

  """
  def get_riddle!(id), do: Repo.get!(Riddle, id)

  @doc """
  Creates a riddle.

  ## Examples

      iex> create_riddle(%{field: value})
      {:ok, %Riddle{}}

      iex> create_riddle(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_riddle(attrs \\ %{}) do
    %Riddle{}
    |> Riddle.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a riddle.

  ## Examples

      iex> update_riddle(riddle, %{field: new_value})
      {:ok, %Riddle{}}

      iex> update_riddle(riddle, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_riddle(%Riddle{} = riddle, attrs) do
    riddle
    |> Riddle.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a riddle.

  ## Examples

      iex> delete_riddle(riddle)
      {:ok, %Riddle{}}

      iex> delete_riddle(riddle)
      {:error, %Ecto.Changeset{}}

  """
  def delete_riddle(%Riddle{} = riddle) do
    Repo.delete(riddle)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking riddle changes.

  ## Examples

      iex> change_riddle(riddle)
      %Ecto.Changeset{data: %Riddle{}}

  """
  def change_riddle(%Riddle{} = riddle, attrs \\ %{}) do
    Riddle.changeset(riddle, attrs)
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `mix test test/riddlr/games_test.exs`
Expected: All tests pass

**Step 6: Run full test suite**

Run: `mix test`
Expected: All tests pass

**Step 7: Commit**

Run: `git add . && git commit -m "feat: add CRUD functions to Games context with comprehensive tests"`
Expected: Commit successful

---

## Task 3: Create Gameplay Context Stub

**Files:**
- Create: `lib/riddlr/gameplay.ex`
- Create: `test/riddlr/gameplay_test.exs`

**Step 1: Create Gameplay context module**

Create `lib/riddlr/gameplay.ex`:

```elixir
defmodule Riddlr.Gameplay do
  @moduledoc """
  The Gameplay context.

  Handles ephemeral game state including answer submissions,
  cooldowns, and real-time player interactions.

  This context will be fully implemented in Phase 9.
  """

  # Placeholder for Phase 9 implementation
  # Will include:
  # - ETS-based answer storage
  # - Cooldown management
  # - Answer validation
  # - Phoenix Presence for player tracking
end
```

**Step 2: Create basic test file**

Create `test/riddlr/gameplay_test.exs`:

```elixir
defmodule Riddlr.GameplayTest do
  use Riddlr.DataCase

  alias Riddlr.Gameplay

  describe "gameplay context" do
    test "context module exists" do
      assert Code.ensure_loaded?(Gameplay)
    end
  end
end
```

**Step 3: Run test**

Run: `mix test test/riddlr/gameplay_test.exs`
Expected: Test passes

**Step 4: Commit**

Run: `git add . && git commit -m "feat: add Gameplay context stub for Phase 9"`
Expected: Commit successful

---

## Task 4: Add Sample Seeds

**Files:**
- Modify: `priv/repo/seeds.exs`

**Step 1: Add sample riddles to seeds**

In `priv/repo/seeds.exs`, add:

```elixir
# Sample riddles for testing and development
alias Riddlr.Games

riddles = [
  %{
    name: "The Keyboard",
    description: "What has keys but no locks, space but no room, and you can enter but can't go inside?",
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
    description: "I have cities, but no houses. I have mountains, but no trees. I have water, but no fish. What am I?",
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
    description: "What runs but never walks, has a mouth but never talks, has a bed but never sleeps?",
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
```

**Step 2: Run seeds**

Run: `mix run priv/repo/seeds.exs`
Expected: 6 riddles created successfully

**Step 3: Verify seeds in IEx**

Run: `iex -S mix`
Then: `Riddlr.Games.list_riddles() |> Enum.map(&{&1.name, &1.difficulty})`
Expected: List of 6 riddles with names and difficulties

**Step 4: Commit**

Run: `git add priv/repo/seeds.exs && git commit -m "feat: add sample riddle seeds for development"`
Expected: Commit successful

---

## Task 5: Verify Complete Implementation

**Files:**
- All previously created/modified files

**Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass (should be ~100+ tests now)

**Step 2: Check code formatting**

Run: `mix format --check-formatted`
Expected: All files properly formatted (or run `mix format` if needed)

**Step 3: Verify in IEx**

Run: `iex -S mix`

Test CRUD operations:
```elixir
# List riddles
Riddlr.Games.list_riddles()

# Get specific riddle
riddle = Riddlr.Games.get_riddle!(1)

# Create new riddle
{:ok, new_riddle} = Riddlr.Games.create_riddle(%{
  name: "Test Riddle",
  description: "A test description",
  answers: ["test"],
  solve_time: 60,
  category: "test",
  difficulty: "easy"
})

# Update riddle
Riddlr.Games.update_riddle(new_riddle, %{name: "Updated Test"})

# Delete riddle
Riddlr.Games.delete_riddle(new_riddle)
```

Expected: All operations work correctly

**Step 4: Verify database schema**

Run: `mix ecto.migrate`
Expected: Already up to date

Check database:
```sql
\d riddles
```
Expected: Table structure matches schema with indices

**Step 5: Check git status**

Run: `git status`
Expected: Clean working tree

**Step 6: View commit history**

Run: `git log --oneline -10`
Expected: See all 5 commits from this phase

---

## Verification Checklist

- [ ] Riddle schema created with all required fields
- [ ] play_status enum validated (closed/scheduled/ready/live/completed/archived)
- [ ] publish_status enum validated (draft/published)
- [ ] difficulty enum validated (easy/medium/hard/expert)
- [ ] answers array requires at least one answer
- [ ] Indices created on play_status, live_date, category, first_solver_id
- [ ] CRUD functions work correctly
- [ ] All tests pass (changeset validation, CRUD, enums)
- [ ] Gameplay context stub created
- [ ] 6 sample riddles seeded
- [ ] Code formatted and committed

---

## Next Steps

After completing Phase 4:
- **Phase 5**: Admin Area & Riddle Management (CRUD UI with role-based auth)
- **Phase 6**: Tag System (tag management and riddle tagging)
- **Phase 7**: Game Lifecycle State Machine (play_status transitions with Oban)

---

## Notes

- Gameplay context is a stub - will be implemented in Phase 9
- first_solver_id references users table but doesn't enforce presence (allows nil)
- play_status defaults to "closed", publish_status to "draft"
- Indices optimize common queries (filtering by status, scheduling by live_date)
- Seeds include mix of published and draft riddles for testing
