# Codebase Analysis: Phoenix Patterns for Riddlr

## Project Structure

- **Web module**: `RiddlrWeb`
- **Business logic module**: `Riddlr`
- **Primary context**: `Riddlr.Games`
- **Naming convention**: snake_case for files/functions, PascalCase for modules

## Phoenix Version & Modern Patterns

- **Phoenix version**: 1.8.3
- **Phoenix LiveView version**: 1.1.0
- **Scopes**: Not currently used in this codebase (using session-based auth instead)
- **Verified routes**: Using ~p sigil throughout (Phoenix 1.8+)
- **FallbackController**: Not currently used
- **PubSub in contexts**: YES - active broadcast pattern in Games context

## Riddle Schema (`lib/riddlr/games/riddle.ex`)

### Fields
```elixir
schema "riddles" do
  field :name, :string
  field :description, :string
  field :answers, {:array, :string}, default: []
  field :play_status, :string, default: "closed"
  field :solve_time, :integer, default: @solve_time
  field :difficulty, :string
  field :hint, :string
  field :hint_delay, :integer, default: @hint_delay
  field :live_date, :utc_datetime
  field :publish_status, :string, default: "draft"
  field :first_solve_time, :integer
  field :completion_rate, :float
  field :average_solve_time, :float

  belongs_to :category, Riddlr.Games.Category
  belongs_to :first_solver, Riddlr.Accounts.User

  timestamps(type: :utc_datetime)
end
```

### Play Status States & Valid Transitions

Valid play_statuses: `~w(closed scheduled ready live completed archived)`

**State Machine Definition**:
```elixir
@valid_transitions %{
  "closed" => ["scheduled"],
  "scheduled" => ["ready", "closed"],
  "ready" => ["live", "closed"],
  "live" => ["completed"],
  "completed" => ["archived"],
  "archived" => []
}
```

**State Flow Diagram**:
```
closed → scheduled → ready → live → completed → archived
         ↓                   ↓
         └─────── closed ←───┘
```

### Publish Status States

Valid publish_statuses: `~w(draft published)`

**Validation Rule**:
- Only published riddles can transition play_status
- When `publish_status` changes from "published" to "draft", ALL pending Oban jobs are cancelled

### Key Validation Rules

1. `play_status` must be one of the valid states
2. `play_status` transitions must follow `@valid_transitions` map
3. `answers` must have at least one non-empty string
4. `solve_time` must be > 0
5. `hint_delay` must be >= 0
6. `completion_rate` must be between 0.0 and 100.0
7. Foreign key constraints on `category_id` and `first_solver_id`

## Games Context API (`lib/riddlr/games.ex`)

### Primary Functions

#### CRUD Operations
- `list_riddles()` - returns all riddles with category preloaded, ordered by insertion (newest first)
- `get_riddle!(id)` - returns single riddle with category preloaded
- `create_riddle(attrs)` - creates new riddle, returns with category preloaded
- `update_riddle(riddle, attrs)` - updates riddle; cancels all pending jobs if publish_status changes to draft
- `delete_riddle(riddle)` - soft delete not implemented
- `change_riddle(riddle, attrs)` - returns changeset for validation

#### State Transition Functions

```elixir
def schedule_riddle(%Riddle{} = riddle, live_date)
```
- **Transitions**: closed → scheduled
- **Preconditions**:
  - current state is "closed"
  - live_date is in future
  - must be published status (enforced by workers, not here)
- **Side effects**:
  - Updates riddle with new status and live_date
  - **Enqueues 2 jobs** (via Multi):
    1. `ReadyRiddleTransitionWorker` scheduled 5 min before live_date
    2. `LiveRiddleTransitionWorker` scheduled at live_date
  - Broadcasts `:riddle_scheduled` event to topic "games:riddle:scheduled"
- **Return**: `{:ok, riddle}` or `{:error, reason}`

```elixir
def ready_riddle(riddle_id)
```
- **Transitions**: scheduled → ready
- **Called by**: `ReadyRiddleTransitionWorker` (5 min before live)
- **Side effects**: Broadcasts `:riddle_ready` event to topic "games:riddle:ready"
- **Return**: `{:ok, riddle}` or `{:error, changeset}`

```elixir
def start_riddle(riddle_id)
```
- **Transitions**: ready → live
- **Called by**: `LiveRiddleTransitionWorker` (at live_date)
- **Side effects**: Broadcasts `:riddle_started` event to topic "games:riddle:started"
- **Return**: `{:ok, riddle}` or `{:error, changeset}`

```elixir
def complete_riddle(riddle_id)
```
- **Transitions**: live → completed
- **Preconditions**: solve_time has expired (called by timer logic, not yet implemented)
- **Side effects**:
  - Updates riddle status to completed
  - **Enqueues** `ArchiveRiddleTransitionWorker` with 180 second (3 min) delay
  - Broadcasts `:riddle_completed` event to topic "games:riddle:completed"
- **Return**: `{:ok, riddle}` or `{:error, changeset}`

```elixir
def archive_riddle(riddle_id)
```
- **Transitions**: completed → archived (final state)
- **Called by**: `ArchiveRiddleTransitionWorker` (3 min after completed)
- **Side effects**: Broadcasts `:riddle_archived` event to topic "games:riddle:archived"
- **Return**: `{:ok, riddle}` or `{:error, changeset}`

#### Job Management
```elixir
def cancel_riddle_jobs(riddle_id)
```
- **Purpose**: Cancel all pending Oban jobs for a riddle
- **States targeted**: "available", "scheduled", "retryable"
- **Called when**: publish_status changes from "published" to "draft"
- **Return**: `{:ok, count}` where count = number of cancelled jobs
- **Implementation**: Updates Oban jobs directly via `Repo.update_all`

### Design Patterns

#### Ecto.Multi Usage
**ALL** state transitions use `Ecto.Multi` to:
1. Atomically update riddle status
2. Insert Oban jobs (for schedule_riddle, complete_riddle)
3. Broadcast PubSub messages
4. Rollback everything if any step fails

**Example Pattern**:
```elixir
Multi.new()
|> Multi.update(:riddle, changeset)
|> Multi.insert(:job, fn %{riddle: updated_riddle} ->
  %{riddle_id: updated_riddle.id}
  |> SomeWorker.new(scheduled_at: future_time)
end)
|> Multi.run(:broadcast, fn _, %{riddle: updated_riddle} ->
  Phoenix.PubSub.broadcast(Riddlr.PubSub, "topic", {:event, updated_riddle})
  {:ok, :broadcasted}
end)
|> Repo.transaction()
```

#### PubSub Broadcast Topics
| Function | Topic | Event |
|----------|-------|-------|
| schedule_riddle | "games:riddle:scheduled" | {:riddle_scheduled, riddle} |
| ready_riddle | "games:riddle:ready" | {:riddle_ready, riddle} |
| start_riddle | "games:riddle:started" | {:riddle_started, riddle} |
| complete_riddle | "games:riddle:completed" | {:riddle_completed, riddle} |
| archive_riddle | "games:riddle:archived" | {:riddle_archived, riddle} |

## Oban Worker Patterns (`lib/riddlr/workers/`)

### Three Existing Workers

All workers follow the same pattern:

```elixir
defmodule Riddlr.Workers.{SomeWorker} do
  use Oban.Worker,
    queue: :game_lifecycle,
    max_attempts: 3,
    unique: [period: {1, :hour}, keys: [:riddle_id]]

  alias Riddlr.{Games, Repo}
  alias Riddlr.Games.Riddle

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
    case Repo.get(Riddle, id) do
      nil ->
        {:cancel, "Riddle #{id} not found"}

      riddle ->
        cond do
          riddle.publish_status != "published" ->
            {:cancel, "Riddle not published (current: #{riddle.publish_status})"}

          riddle.play_status != "expected_status" ->
            {:cancel, "Already transitioned (current: #{riddle.play_status})"}

          true ->
            case Games.transition_function(id) do
              {:ok, _riddle} -> :ok
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end
end
```

### Worker Configuration

| Property | Value |
|----------|-------|
| Queue | `:game_lifecycle` |
| Max Attempts | 3 |
| Unique Constraint | 1 hour period on `riddle_id` |
| Args Format | STRING keys: `%{"riddle_id" => id}` |

### Worker Idempotency Pattern

All workers implement idempotency via:

1. **State Checks**: Verify riddle is in expected state before transitioning
2. **Publish Status Check**: MUST be "published" or worker cancels
3. **Cancellation Logic**: Returns `{:cancel, reason}` for non-retryable failures
4. **Unique Constraint**: Prevents duplicate jobs for same riddle within 1 hour window

### Existing Workers

#### ReadyRiddleTransitionWorker
- **Scheduled**: 5 minutes before `live_date` (via `schedule_riddle`)
- **Transitions**: scheduled → ready
- **Calls**: `Games.ready_riddle(id)`

#### LiveRiddleTransitionWorker
- **Scheduled**: At exact `live_date` (via `schedule_riddle`)
- **Transitions**: ready → live
- **Calls**: `Games.start_riddle(id)`

#### ArchiveRiddleTransitionWorker
- **Scheduled**: 180 seconds (3 min) after completion (via `complete_riddle`)
- **Transitions**: completed → archived
- **Calls**: `Games.archive_riddle(id)`

### Job Enqueueing Pattern

Jobs are created inline within Multi operations:

```elixir
Multi.insert(:job_key, fn %{riddle: updated_riddle} ->
  %{riddle_id: updated_riddle.id}
  |> SomeWorker.new(scheduled_at: future_time)
  # or: |> SomeWorker.new(schedule_in: seconds)
end)
```

**Key Options**:
- `scheduled_at: DateTime` - absolute time to run
- `schedule_in: seconds` - relative delay in seconds

## Admin LiveView Patterns

### Index View (`lib/riddlr_web/live/admin/riddle_live/index.ex`)

- **Uses streams**: `:riddles` stream for list rendering
- **Live actions**: `:index`, `:new`, `:edit`, `:show`
- **Preloading**: `list_riddles()` returns with category preloaded
- **Events**:
  - `delete` - requires authorization check
  - Auto-resets stream on :index action
- **Broadcasting**: Handles `:riddle_saved` message to insert/update riddles at top (index 0)
- **Authorization**: `Authorization.has_permission?(user, :manage_riddles)` checked in event handlers

### Form Component (`lib/riddlr_web/live/admin/riddle_live/form_component.ex`)

**Key Features**:
1. **Answers Array Conversion**:
   - Displays as textarea (newline-separated)
   - Converts to/from array before saving via `prepare_params_for_changeset`

2. **Live Date Handling**:
   - Input type: `datetime-local` HTML5
   - Parses to UTC via `NaiveDateTime.from_iso8601` then `DateTime.from_naive!`
   - Can be nil (riddle doesn't require scheduling)

3. **Auto-Schedule Logic**:
   - Function: `should_auto_schedule?/3`
   - Triggers when:
     - Riddle is currently closed
     - live_date is set and in future
     - user didn't manually select incompatible play_status
   - Calls `Games.schedule_riddle(riddle, live_date)` instead of `update_riddle`

4. **Multi-step Save Response**:
   - When scheduling: returns `{:ok, %{riddle: ..., ready_job: ..., live_job: ...}}`
   - When updating: returns `{:ok, riddle}`
   - Shows formatted job scheduled times in flash message

5. **Form Validation**:
   - Real-time: `validate` event triggers `Games.change_riddle` with `:validate` action
   - Server-side: validates against schema constraints

6. **Authorization**: Checked on "save" event, not in mount (must check in events)

**Helper Functions**:
- `prepare_riddle_for_form/1` - converts array answers to newline string for display
- `prepare_params_for_changeset/1` - converts textarea string to array of answers
- `parse_live_date/1` - safely parses HTML datetime-local input
- `should_auto_schedule?/3` - determines if scheduling should auto-trigger

## Database Migrations & Indexing

### Create Riddles Table
```elixir
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
```

### Indexes Present
- `play_status` - for filtering by state
- `live_date` - for finding riddles to transition
- `category` - for finding riddles by category
- `first_solver_id` - for finding first solvers

## Testing Patterns

### Test Infrastructure

**Test Case Base**: `Riddlr.DataCase` (async: true by default)

**Oban Testing**: Uses `Oban.Testing` module
```elixir
use Oban.Testing, repo: Riddlr.Repo
```

**Fixtures**: `Riddlr.GamesFixtures` provides:
- `riddle_fixture(attrs)` - creates riddle with defaults
- Auto-creates default "logic" category if needed
- Returns riddle with category preloaded (matches Games API)

### Example Test Pattern

```elixir
test "transitions scheduled riddle to ready" do
  riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "published"})

  assert :ok = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
  assert Riddlr.Repo.reload(riddle).play_status == "ready"
end

test "cancels if riddle is not published" do
  riddle = riddle_fixture(%{play_status: "scheduled", publish_status: "draft"})

  assert {:cancel, message} = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
  assert message =~ "not published"
end
```

## Oban Configuration

**Queue Configuration** (`config/config.exs`):
```elixir
queues: [game_lifecycle: 5, mailers: 3, default: 5]
```

- `game_lifecycle`: 5 concurrent workers (for riddle state transitions)
- `mailers`: 3 concurrent workers
- `default`: 5 concurrent workers

## Conventions to Follow for New Features

1. **State Machine Additions**:
   - Add new state to `@play_statuses` list
   - Update `@valid_transitions` map
   - Add validation in schema's `validate_play_status_transition/1`

2. **New Transition Functions**:
   - Use `Ecto.Multi` for atomicity
   - Always include broadcast step
   - Include state validation in cond clause
   - Return `{:ok, riddle}` or `{:error, reason}`

3. **New Worker Creation**:
   - Queue: `:game_lifecycle`
   - Max attempts: 3
   - Unique: `[period: {1, :hour}, keys: [:riddle_id]]`
   - Args: STRING keys only (`%{"riddle_id" => id}`)
   - Implement idempotency via state checks
   - Check `publish_status == "published"` before transitioning
   - Return `:ok`, `{:error, reason}`, or `{:cancel, reason}`

4. **LiveView Updates**:
   - Forms use `:live_component`
   - Handle `:riddle_saved` in index.ex via `handle_info/2`
   - Check authorization in event handlers, not mount
   - Use streams for lists
   - Preload associations in context functions, not in view

5. **PubSub Conventions**:
   - Topic format: `"games:riddle:{action}"` (e.g., "games:riddle:scheduled")
   - Broadcast in Multi operations within context functions
   - Subscribe in LiveViews with `Phoenix.PubSub.subscribe(Riddlr.PubSub, topic)`

6. **Validation**:
   - State-specific validation in changeset
   - Publish status must be "published" for workers (not validated in schema)
   - Dates must be UTC (use `DateTime.utc_now()`)

## Key Implementation Notes

### "Publish Status Enforcement" Pattern
Workers check `publish_status == "published"` before acting. This allows:
- Drafting riddles without triggering transitions
- Unpublishing a riddle (changing to draft) cancels all pending jobs
- Re-publishing enables jobs to run again

### Preloading Strategy
- Context functions (`list_riddles`, `get_riddle!`, `create_riddle`) always preload `:category`
- Returns riddle with category available for display
- LiveViews don't need to preload; data comes from context

### No Direct Repo Calls in LiveView
- All data access goes through Games context functions
- No `Repo.all(Riddle)` or `Repo.get(Riddle, id)` in views
- Authorization is context's responsibility... wait, no: Authorization.has_permission is checked in views
- But data access is always via Games context

### Errors in Multi Transactions
Pattern for transaction result handling:
```elixir
|> Repo.transaction()
|> case do
  {:ok, %{riddle: riddle}} -> {:ok, riddle}
  {:ok, %{riddle: riddle, ready_job: job, live_job: job}} -> {:ok, ...}  # Multiple returns
  {:error, :riddle, changeset, _} -> {:error, changeset}
  {:error, _failed_op, reason, _} -> {:error, reason}
end
```

## Anti-patterns to Avoid

1. **NO** direct Repo queries in controllers/LiveViews - use context functions
2. **NO** side effects in schema callbacks
3. **NO** state transitions without Multi (atomicity required)
4. **NO** workers without unique constraint
5. **NO** atom keys in worker args (security risk, always use strings)
6. **NO** skipping publish_status check in workers
7. **NO** adding publish_status enforcement in schema changeset (must be in workers)

## Files to Reference

- **Schema**: `/Users/gmacgregor/src/elixir-projects/riddlr/lib/riddlr/games/riddle.ex`
- **Context**: `/Users/gmacgregor/src/elixir-projects/riddlr/lib/riddlr/games.ex`
- **Workers**: `/Users/gmacgregor/src/elixir-projects/riddlr/lib/riddlr/workers/`
- **LiveView Index**: `/Users/gmacgregor/src/elixir-projects/riddlr/lib/riddlr_web/live/admin/riddle_live/index.ex`
- **Form Component**: `/Users/gmacgregor/src/elixir-projects/riddlr/lib/riddlr_web/live/admin/riddle_live/form_component.ex`
- **Tests**: `/Users/gmacgregor/src/elixir-projects/riddlr/test/riddlr/workers/`
- **Fixtures**: `/Users/gmacgregor/src/elixir-projects/riddlr/test/support/fixtures/games_fixtures.ex`
