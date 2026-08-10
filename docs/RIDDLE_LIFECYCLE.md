# Riddle Play Status Lifecycle

This document describes the complete lifecycle of riddles in the Riddlr system, from creation through archival.

## Overview

Riddles move through six distinct play statuses in a controlled sequence:

```
closed → scheduled → ready → live → completed → archived
```

Each transition is either manual (admin-initiated) or automatic (worker/event-triggered).

## State Diagram

```
┌─────────┐
│ closed  │ Initial state, not scheduled
└────┬────┘
     │ Admin publishes + sets live_date
     ▼
┌─────────┐
│scheduled│ Published, workers scheduled
└────┬────┘
     │ ReadyTransitionWorker (5 min before)
     ▼
┌─────────┐
│  ready  │ Ready to go live
└────┬────┘
     │ LiveTransitionWorker (at live_date)
     ▼
┌─────────┐
│  live   │ Accepting player answers
└────┬────┘
     │ First correct answer
     ▼
┌─────────┐
│completed│ Cooldown period starts
└────┬────┘
     │ ArchiveTransitionWorker (after cooldown)
     ▼
┌─────────┐
│archived │ Final state
└─────────┘
```

## State Descriptions

### closed
- **Initial state** for all new riddles
- Not scheduled for play
- Can be scheduled by setting `publish_status: "published"` and `live_date`
- Can transition to: `scheduled`

### scheduled
- Riddle is published with a future `live_date`
- Two Oban workers are scheduled:
  - `ReadyTransitionWorker` - 5 minutes before `live_date`
  - `LiveTransitionWorker` - at `live_date`
- Can transition to: `ready`, `closed` (manual admin action or draft rollback)

### ready
- Riddle is 5 minutes away from going live
- Triggered automatically by `ReadyTransitionWorker`
- Visible in admin UI as "ready to launch"
- Can transition to: `live`, `closed` (manual admin action or draft rollback)

### live
- Riddle is currently active and accepting answers
- Triggered automatically by `LiveTransitionWorker`
- Players can submit answers and earn points
- Can transition to: `completed` (only via first correct answer)

### completed
- First correct answer has been received
- `first_solver` and `first_solve_time` are recorded
- Cooldown period begins (default: 3 minutes)
- `ArchiveTransitionWorker` is scheduled to run after cooldown
- Can transition to: `archived` (automatic only)

### archived
- Riddle has been moved to the archive
- No longer accepting answers
- Statistics are finalized
- Terminal state - no further transitions allowed

## Transition Triggers

### Manual (Admin-Initiated)

#### Publishing and Scheduling
```elixir
# Publishing a closed riddle with a future live_date schedules it: one save
# writes the row and the jobs.
{:ok, riddle} = Games.save_riddle(riddle, %{
  publish_status: "published",
  live_date: ~U[2026-04-01 14:00:00Z]
})
# => play_status: "scheduled"
# => 2 Oban jobs scheduled
```

#### Draft Rollback
```elixir
# Moving to draft cancels all pending workers
{:ok, riddle} = Games.save_riddle(riddle, %{
  publish_status: "draft"
})
# => play_status: "closed" (if was scheduled/ready)
# => All Oban jobs cancelled
```

### Automatic (Worker/Event-Triggered)

#### scheduled → ready
- Triggered by: `ReadyTransitionWorker`
- When: 5 minutes before `live_date`
- Action: Updates `play_status` to "ready"

#### ready → live
- Triggered by: `LiveTransitionWorker`
- When: At `live_date`
- Action: Updates `play_status` to "live"

#### live → completed
- Triggered by: First correct answer submission
- When: Player submits correct answer
- Action: Updates `play_status` to "completed", records solver

#### completed → archived
- Triggered by: `ArchiveTransitionWorker`
- When: After `archive_after_seconds` (default: 3)
- Action: Updates `play_status` to "archived"

## Advanced Features

### Rescheduling

When an admin changes the `live_date` of a scheduled riddle:

1. System cancels all pending workers for the riddle
2. New workers are scheduled based on new `live_date`
3. `play_status` remains "scheduled"

**Example**:
```elixir
# Riddle scheduled for April 1 at 2 PM
riddle = %Riddle{
  play_status: "scheduled",
  live_date: ~U[2026-04-01 14:00:00Z]
}

# Admin reschedules to April 5 at 3 PM
{:ok, riddle} = Games.save_riddle(riddle, %{
  live_date: ~U[2026-04-05 15:00:00Z]
})
# => Old jobs cancelled
# => New jobs scheduled for April 5
```

### Draft Rollback

When an admin moves a scheduled/ready riddle back to draft:

1. `publish_status` changes from "published" to "draft"
2. All pending Oban workers are cancelled
3. `play_status` reverts to "closed"
4. `live_date` remains set but is no longer enforced

**Example**:
```elixir
# Riddle is scheduled
riddle = %Riddle{
  publish_status: "published",
  play_status: "scheduled",
  live_date: ~U[2026-04-01 14:00:00Z]
}

# Admin moves to draft
{:ok, riddle} = Games.save_riddle(riddle, %{
  publish_status: "draft"
})
# => play_status: "closed"
# => All jobs cancelled
```

**Important**: Draft rollback is only allowed for `scheduled` and `ready` states. Once a riddle is `live` or beyond, it cannot be moved back to draft.

### Archive Cooldown

The `archive_after_seconds` field controls how long a riddle remains in "completed" status before archiving.

**Default behavior** (3 minutes):
```elixir
riddle = %Riddle{
  play_status: "completed",
  archive_after_seconds: 3  # default
}
# => Archives 3 minutes after completion
```

**Immediate archival** (0 minutes):
```elixir
riddle = %Riddle{
  archive_after_seconds: 0
}
# => Archives immediately after completion
```

**Custom cooldown**:
```elixir
riddle = %Riddle{
  archive_after_seconds: 10
}
# => Archives 10 minutes after completion
```

## Oban Workers

### ReadyTransitionWorker
- **Queue**: `default`
- **Trigger**: Scheduled 5 minutes before `live_date`
- **Action**: Transitions riddle from `scheduled` to `ready`
- **Idempotent**: Safe to retry
- **Enforces**: `publish_status: "published"` check

### LiveTransitionWorker
- **Queue**: `default`
- **Trigger**: Scheduled at `live_date`
- **Action**: Transitions riddle from `ready` to `live`
- **Idempotent**: Safe to retry
- **Enforces**: `publish_status: "published"` check

### ArchiveTransitionWorker
- **Queue**: `default`
- **Trigger**: Scheduled `archive_after_seconds` after completion
- **Action**: Transitions riddle from `completed` to `archived`
- **Idempotent**: Safe to retry
- **No publish_status check**: Archives regardless of publish status

### Worker Configuration

All workers:
- Use string keys for job args: `%{"riddle_id" => id}`
- Are idempotent and safe to retry
- Check current state before transition (no-op if invalid)
- Use Oban's unique jobs feature to prevent duplicates

## Testing

### Integration Tests

Full lifecycle integration test:
```elixir
test "full riddle lifecycle from scheduled to archived" do
  # Create riddle
  riddle = insert(:riddle, archive_after_seconds: 0)

  # Schedule it
  {:ok, riddle} = Games.save_riddle(riddle, %{"live_date" => live_date})
  assert riddle.play_status == "scheduled"

  # Transition to ready (worker)
  assert {:ok, _} = perform_job(ReadyTransitionWorker, %{"riddle_id" => riddle.id})
  riddle = Repo.reload!(riddle)
  assert riddle.play_status == "ready"

  # Transition to live (worker)
  assert {:ok, _} = perform_job(LiveTransitionWorker, %{"riddle_id" => riddle.id})
  riddle = Repo.reload!(riddle)
  assert riddle.play_status == "live"

  # Complete (player action)
  {:ok, riddle} = Games.transition(riddle.id, :completed, %{first_solver_id: user.id})
  assert riddle.play_status == "completed"

  # Archive (worker, immediate with cooldown: 0)
  assert {:ok, _} = perform_job(ArchiveTransitionWorker, %{"riddle_id" => riddle.id})
  riddle = Repo.reload!(riddle)
  assert riddle.play_status == "archived"
end
```

### Unit Tests

Each worker has dedicated tests verifying:
- State transitions
- publish_status enforcement
- Idempotency
- Error handling

## Admin UI

### Index Page (/admin/riddles)

**Status Badge Colors**:
- `closed`: Gray
- `scheduled`: Blue
- `ready`: Yellow/Warning
- `live`: Green/Success
- `completed`: Purple/Info
- `archived`: Gray/Secondary

**Live Date Display**:
- Shows scheduled time for `scheduled` and `ready` riddles
- Empty for other statuses

### Edit/Form Page

**Status Display**:
- Current `play_status` shown as badge in header
- Current `publish_status` shown in form

**Reschedule Warning**:
- When editing `live_date` of scheduled riddle
- Alert shown: "Changing the live date will reschedule the riddle workers"

**Draft Rollback Warning**:
- When changing `publish_status` from "published" to "draft" for scheduled/ready riddle
- Alert shown: "Moving to draft will cancel scheduled workers and reset play status"

## Common Workflows

### Schedule a New Riddle
1. Admin creates riddle (status: `closed`, publish: `draft`)
2. Admin sets `live_date` and changes `publish_status` to "published"
3. System transitions to `scheduled` and schedules workers
4. Workers automatically transition through `ready` → `live`
5. First player completes, system moves to `completed`
6. After cooldown, system archives

### Reschedule a Riddle
1. Admin edits `live_date` of scheduled riddle
2. System cancels old workers
3. System schedules new workers
4. Lifecycle continues as normal

### Cancel a Scheduled Riddle
1. Admin changes `publish_status` to "draft"
2. System cancels all workers
3. `play_status` reverts to "closed"
4. Riddle can be rescheduled later

### Immediate Archive (Skip Cooldown)
1. Admin sets `archive_after_seconds: 0` before scheduling
2. When riddle completes, it archives immediately

## Database Schema

Relevant fields in `riddles` table:

```elixir
field :play_status, :string, default: "closed"
field :publish_status, :string, default: "draft"
field :live_date, :utc_datetime
field :archive_after_seconds, :integer, default: 3
field :first_solver_id, :bigint
field :first_solve_time, :integer
```

## Related Modules

- `Riddlr.Games.Riddle` - Schema with state validation
- `Riddlr.Games` - Context with scheduling/transition functions
- `Riddlr.Workers.ReadyTransitionWorker` - scheduled → ready
- `Riddlr.Workers.LiveTransitionWorker` - ready → live
- `Riddlr.Workers.ArchiveTransitionWorker` - completed → archived
- `RiddlrWeb.Admin.RiddleLive.FormComponent` - Admin form with warnings

## Implementation Notes

### State Validation

The schema enforces valid state transitions:
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

Attempting invalid transitions will result in validation errors.

### Worker Uniqueness

All workers use Oban's unique jobs feature:
```elixir
new(%{"riddle_id" => riddle.id},
  scheduled_at: scheduled_time,
  unique: [period: :infinity, keys: [:worker, :args]]
)
```

This prevents duplicate jobs for the same riddle and transition.

### Publish Status Enforcement

Ready and Live workers enforce `publish_status: "published"`:
```elixir
riddle = Repo.get!(Riddle, riddle_id)
if riddle.publish_status != "published" do
  {:cancel, "Riddle is not published"}
else
  # proceed with transition
end
```

This ensures riddles moved to draft don't auto-transition even if workers weren't cancelled.

## Troubleshooting

### Riddle stuck in "scheduled"
- Check Oban dashboard for pending/failed jobs
- Verify `live_date` is in the future
- Ensure workers were actually scheduled (check `oban_jobs` table)

### Workers not running
- Check Oban configuration in `config/config.exs`
- Verify `default` queue is enabled
- Check for worker errors in Oban dashboard

### Cannot reschedule riddle
- Ensure riddle is still in `scheduled` or `ready` state
- Cannot reschedule `live`, `completed`, or `archived` riddles
- Check for validation errors on `live_date` update

### Archive not happening
- Verify `archive_after_seconds` is set
- Check for pending `ArchiveTransitionWorker` job
- Ensure riddle is in `completed` status
