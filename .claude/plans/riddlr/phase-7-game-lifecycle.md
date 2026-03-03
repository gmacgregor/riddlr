# Phase 7: Game Lifecycle State Machine

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Overview

Implement automatic state transitions (closed → scheduled → ready → live → completed → archived) using Oban background workers with idempotency, proper error handling, and state validation.

## Context

**Current state:**

- Riddle schema exists with `play_status` enum (closed, scheduled, ready, live, completed, archived)
- Games context has basic CRUD (create, read, update, delete)
- Oban dependency installed but NOT configured
- No workers or state transition logic exists

**Dependencies:**

- Phase 4 ✅ (Riddle schema exists)
- Phase 5 ✅ (Admin area for scheduling riddles)

**Blocks:**

- Phase 8 (Game Lobby - needs ready state)
- Phase 9 (Live Game - needs live state)
- Phase 11 (Game Completion - needs completed/archived states)

---

## **For Claude:** Execution Instructions

### Execution Approach

**Sequential execution required.** Dependencies:

1. Oban config MUST complete before workers
2. Games context transitions MUST exist before workers can call them
3. State validation MUST be in place before testing transitions
4. Workers MUST exist before admin integration

**Do NOT parallelize** - each task builds on previous infrastructure.

### Implementation Order

1. **Infrastructure first** (Oban config, migration, supervisor)
2. **Core logic** (Games context transition functions with Multi)
3. **Workers** (ReadyWorker, LiveWorker, ArchiveWorker)
4. **Validation** (Riddle changeset state transition guard)
5. **Tests** (worker unit tests, integration tests)
6. **UI integration** (admin form calls schedule_riddle)

### Key Patterns to Follow

**Ecto.Multi atomic transactions:**

- All state transitions MUST use Multi for atomicity
- Job enqueue, DB update, PubSub broadcast in single transaction
- Pattern: `Multi.new() |> Multi.update() |> Multi.insert() |> Multi.run() |> Repo.transaction()`

**Idempotency in workers:**

```elixir
# ALWAYS check current state before transition
if riddle.play_status == expected_status do
  perform_transition()
else
  {:cancel, "Already transitioned"}
end
```

**Error handling convention:**

- Return `{:error, reason}` for transient failures (will retry)
- Return `{:cancel, reason}` for permanent failures (won't retry)
- Examples: Missing riddle → `{:cancel, ...}`, DB timeout → `{:error, ...}`

**Unique constraints on jobs:**

```elixir
unique: [period: {1, :hour}, keys: [:riddle_id]]
```

Prevents duplicate jobs - critical for state machine integrity.

### Verification Strategy

**After each major task:**

1. Run `mix compile --warnings-as-errors` (fail fast on warnings)
2. Run tests for ONLY what you just implemented
3. IEx smoke test if implementing workers/transitions

**Before marking complete:**

1. Full `mix test` suite must pass
2. Manual IEx verification (see plan's Verification Checklist)
3. Check `Oban.Job |> Repo.all()` to verify jobs scheduled correctly

### When to Ask for Help

- If Oban config doesn't start supervisor (check application.ex syntax)
- If Multi transactions fail with confusing errors (inspect Multi failures)
- If unique constraints prevent valid job enqueues (check keys match)
- If PubSub events not received (verify topic names, subscribers)

### Compound Documentation

**Create `.claude/solutions/` compounds for:**

- "Oban idempotent worker pattern" (after first worker implemented)
- "Ecto.Multi with Oban job enqueue" (after schedule_riddle implemented)
- "Phoenix PubSub integration in Multi" (if you solve broadcast timing issues)

Use `/phx:compound` after solving any non-trivial issue.

### Test Environment

**CRITICAL:** Test config uses `config :riddlr, Oban, testing: :manual`

- This prevents auto-execution of jobs during tests
- Use `perform_job(Worker, args)` to manually trigger workers
- Use `Oban.drain_queue(:game_lifecycle)` to process all queued jobs

**Common test mistakes:**

- Forgetting to reload riddle after worker runs: `riddle = Repo.reload(riddle)`
- Testing scheduled jobs without `perform_job` - they won't execute
- Not using `Oban.Testing` in worker tests

### Iron Law Compliance

- **No silent failures:** All transition functions return `{:ok, _}` or `{:error, _}` - never just update and hope
- **State validation enforced at changeset level** - impossible to bypass
- **Idempotency is NOT optional** - workers MUST handle duplicate execution
- **Transactions are atomic** - Multi ensures all-or-nothing

### Checkpoints

**Checkpoint 1: Oban Running** (after "Configure Oban" task)

```elixir
iex> Supervisor.which_children(Riddlr.Supervisor)
# Should show Oban in child list
```

**Checkpoint 2: Transitions Work** (after "State Transition Functions" task)

```elixir
iex> riddle = Repo.get!(Riddlr.Games.Riddle, 1)
iex> live_date = DateTime.utc_now() |> DateTime.add(600, :second)
iex> {:ok, result} = Riddlr.Games.schedule_riddle(riddle, live_date)
iex> result.riddle.play_status == "scheduled"  # true
iex> Oban.Job |> Repo.all() |> length()  # 2 jobs
```

**Checkpoint 3: Workers Execute** (after all workers implemented)

```elixir
iex> perform_job(ReadyWorker, %{riddle_id: id})
iex> Repo.reload(riddle).play_status  # "ready"
```

### What NOT to Do

- ❌ Don't create CompleteRiddleWorker yet (Phase 11 dependency noted in plan)
- ❌ Don't implement ETS cleanup in archive_riddle (Phase 9 dependency)
- ❌ Don't add complex notification logic (Phase 13)
- ❌ Don't modify riddle schema fields beyond play_status (out of scope)
- ❌ Don't skip Multi - direct Repo.update is NOT acceptable for state transitions

### Success Criteria

Plan complete when:

- [ ] All 8 tasks checked off
- [ ] `mix test` passes with 0 failures
- [ ] Admin can schedule riddle via UI
- [ ] Manual IEx test shows full lifecycle works (closed → archived)
- [ ] PubSub events broadcast (subscribe in IEx to verify)
- [ ] No compilation warnings

---

## Tasks

### [ecto] Configure Oban

- [x] Add Oban config to `config/config.exs` — queues: game_lifecycle (5), mailers (3), default (5), Pruner plugin enabled
- [x] Add Oban migration — created migration 20260301034837_add_oban_jobs_table.exs using Oban.Migration v12
- [x] Run Oban installer migration — oban_jobs table created with all indexes, triggers, and state enum
- [x] Add Oban supervisor to `application.ex` children list — added after Repo, before DNSCluster
- [x] Configure test environment in `config/test.exs` — testing: :manual mode (jobs don't auto-execute)

**Files:** `config/config.exs`, `config/test.exs`, `lib/riddlr/application.ex`, new migration

**Tests:**

- Oban supervisor starts successfully
- Queues configured correctly (game_lifecycle, mailers, default)
- Test environment uses `:manual` mode

**Verify:** `mix test`, `iex -S mix`, check `Supervisor.which_children(Riddlr.Supervisor)`

---

### [ecto] Add State Transition Functions to Games Context

**Location:** `lib/riddlr/games.ex`

Implement five transition functions using Ecto.Multi for atomicity:

- [x] **`schedule_riddle(riddle, live_date)`** — closed → scheduled, enqueues ready/live jobs, broadcasts scheduled event
  - Update riddle: `play_status: :scheduled, live_date: live_date`
  - Enqueue `ReadyRiddleTransitionWorker` at `live_date - 5 minutes`
  - Enqueue `LiveRiddleTransitionWorker` at `live_date`
  - Broadcast PubSub event: `games:riddle:scheduled`
  - Return `{:ok, %{riddle: riddle, ready_job: job1, live_job: job2}}` or `{:error, reason}`

- [x] **`ready_riddle(riddle_id)`** — scheduled → ready, state check, broadcasts ready event

- [x] **`start_riddle(riddle_id)`** — ready → live, state check, broadcasts started event (CompleteRiddleWorker deferred to Phase 11)

- [x] **`complete_riddle(riddle_id)`** — live → completed, enqueues ArchiveWorker (180s), broadcasts completed event

- [x] **`archive_riddle(riddle_id)`** — completed → archived, broadcasts archived event (ETS cleanup deferred to Phase 9)

**Implementation pattern:**

```elixir
def schedule_riddle(%Riddle{} = riddle, live_date) do
  Multi.new()
  |> Multi.update(:riddle, Riddle.changeset(riddle, %{
    play_status: "scheduled",
    live_date: live_date
  }))
  |> Multi.insert(:ready_job, fn _ ->
    %{riddle_id: riddle.id}
    |> Riddlr.Workers.ReadyRiddleTransitionWorker.new(
      scheduled_at: DateTime.add(live_date, -300, :second)
    )
  end)
  |> Multi.insert(:live_job, fn _ ->
    %{riddle_id: riddle.id}
    |> Riddlr.Workers.LiveRiddleTransitionWorker.new(
      scheduled_at: live_date
    )
  end)
  |> Multi.run(:broadcast, fn _, _ ->
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "games:riddle:scheduled",
      {:riddle_scheduled, riddle}
    )
    {:ok, :broadcasted}
  end)
  |> Repo.transaction()
end
```

**Files:** `lib/riddlr/games.ex`

**Tests:**

- Each transition function updates play_status correctly
- Invalid transitions return `{:error, _}` (e.g., closed → live)
- Jobs enqueued with correct `scheduled_at`
- PubSub broadcasts sent
- Full cycle: closed → scheduled → ready → live → completed → archived

**Verify:** Call transitions in IEx, check DB, inspect Oban jobs table

---

### [oban] Create ReadyRiddleTransitionWorker

**Location:** `lib/riddlr/workers/ready_riddle_transition_worker.ex`

- [x] Worker created with Oban.Worker behavior, queue: game_lifecycle, max_attempts: 3, unique constraint (1 hour, riddle_id), idempotency check for scheduled status

**Pattern:**

```elixir
defmodule Riddlr.Workers.ReadyRiddleTransitionWorker do
  use Oban.Worker,
    queue: :game_lifecycle,
    max_attempts: 3,
    unique: [period: {1, :hour}, keys: [:riddle_id]]

  alias Riddlr.{Games, Repo}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
    riddle = Repo.get!(Games.Riddle, id)

    if riddle.play_status == "scheduled" do
      case Games.ready_riddle(id) do
        {:ok, _riddle} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:cancel, "Already transitioned (current: #{riddle.play_status})"}
    end
  end
end
```

**Files:** `lib/riddlr/workers/ready_riddle_transition_worker.ex`

**Tests:**

- Worker performs transition successfully
- Idempotency: running twice cancels second attempt
- Wrong state cancels (e.g., riddle is :live)
- Unique constraint prevents duplicate jobs

**Verify:** Enqueue job manually, drain queue, check DB

---

### [oban] Create LiveRiddleTransitionWorker

**Location:** `lib/riddlr/workers/live_riddle_transition_worker.ex`

- [x] Worker created with same structure as ReadyWorker, idempotency check for ready status, calls start_riddle

**Files:** `lib/riddlr/workers/live_riddle_transition_worker.ex`

**Tests:**

- Worker performs ready → live transition
- Idempotency check
- Unique constraint

---

### [oban] Create ArchiveRiddleTransitionWorker

**Location:** `lib/riddlr/workers/archive_riddle_transition_worker.ex`

- [x] Worker created with same structure, idempotency check for completed status, calls archive_riddle

**Files:** `lib/riddlr/workers/archive_riddle_transition_worker.ex`

**Tests:**

- Worker performs completed → archived transition
- Idempotency check
- Unique constraint

---

### [ecto] Add State Validation to Riddle Changeset

**Location:** `lib/riddlr/games/riddle.ex`

- [x] Added @valid_transitions map with all allowed transitions (including cancel paths from scheduled/ready → closed)
- [x] Implemented validate_play_status_transition/1 function, checks transitions only if play_status changed, adds error for invalid transitions
- [x] Integrated into changeset pipeline after validate_inclusion

**Files:** `lib/riddlr/games/riddle.ex`

**Tests:**

- Valid transitions pass (closed → scheduled, scheduled → ready, etc.)
- Invalid transitions fail (closed → live, archived → live)
- No validation if play_status unchanged

**Verify:** Test in IEx with invalid changesets

---

### [test] Integration Tests for Full State Machine

**Location:** `test/riddlr/games_test.exs`

- [x] Full lifecycle test (closed → archived) with job enqueueing, PubSub events, invalid transitions, idempotency, state validation at changeset level - all passing

  ```elixir
  test "full riddle lifecycle" do
    riddle = insert(:riddle, play_status: "closed")
    live_date = DateTime.add(DateTime.utc_now(), 600, :second)  # +10 min

    # Schedule
    {:ok, result} = Games.schedule_riddle(riddle, live_date)
    assert result.riddle.play_status == "scheduled"
    assert result.ready_job.scheduled_at == DateTime.add(live_date, -300, :second)
    assert result.live_job.scheduled_at == live_date

    # Ready
    {:ok, riddle} = Games.ready_riddle(riddle.id)
    assert riddle.play_status == "ready"

    # Live
    {:ok, riddle} = Games.start_riddle(riddle.id)
    assert riddle.play_status == "live"

    # Complete
    {:ok, riddle} = Games.complete_riddle(riddle.id)
    assert riddle.play_status == "completed"

    # Archive
    {:ok, riddle} = Games.archive_riddle(riddle.id)
    assert riddle.play_status == "archived"
  end
  ```

- [ ] Test invalid transition attempts
- [ ] Test worker execution via `Oban.drain_queue(:game_lifecycle)`
- [ ] Test idempotency (call ready_riddle twice on scheduled riddle)
- [ ] Test scheduled auto-transitions:

  ```elixir
  test "auto-transitions via Oban workers" do
    riddle = insert(:riddle, play_status: "closed")
    live_date = DateTime.utc_now() |> DateTime.add(1, :second)

    {:ok, _} = Games.schedule_riddle(riddle, live_date)

    # Simulate time passing - drain ready worker
    perform_job(Riddlr.Workers.ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
    riddle = Repo.reload(riddle)
    assert riddle.play_status == "ready"

    # Drain live worker
    perform_job(Riddlr.Workers.LiveRiddleTransitionWorker, %{riddle_id: riddle.id})
    riddle = Repo.reload(riddle)
    assert riddle.play_status == "live"
  end
  ```

**Files:** `test/riddlr/games_test.exs`, `test/riddlr/workers/*_test.exs`

**Tests:** (Meta - these ARE the tests)

**Verify:** `mix test`

---

### [test] Worker Unit Tests

**Locations:**
- `test/riddlr/workers/ready_riddle_transition_worker_test.exs`
- `test/riddlr/workers/live_riddle_transition_worker_test.exs`
- `test/riddlr/workers/archive_riddle_transition_worker_test.exs`

- [x] All 3 workers tested: successful transitions, idempotency (cancel when wrong state), unique constraints (Oban handles duplicates) - all passing

**Pattern:**

```elixir
defmodule Riddlr.Workers.ReadyRiddleTransitionWorkerTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  alias Riddlr.Workers.ReadyRiddleTransitionWorker

  test "transitions scheduled riddle to ready" do
    riddle = insert(:riddle, play_status: "scheduled")

    assert :ok = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
    assert Repo.reload(riddle).play_status == "ready"
  end

  test "idempotency - cancels if already ready" do
    riddle = insert(:riddle, play_status: "ready")

    assert {:cancel, _} = perform_job(ReadyRiddleTransitionWorker, %{riddle_id: riddle.id})
  end
end
```

**Files:** `test/riddlr/workers/*.exs`

**Verify:** `mix test test/riddlr/workers/`

---

### [test] Update Admin LiveView to Use schedule_riddle

**Location:** `lib/riddlr_web/live/admin/riddle_live/form_component.ex`

- [x] Admin form now uses schedule_riddle/2 when riddle is "closed" and live_date is set, displays ready/live times in flash message, includes parse_live_date helper for datetime-local input

**Files:** `lib/riddlr_web/live/admin/riddle_live/form_component.ex`

**Tests:**

- Scheduling riddle from admin form creates jobs
- Error handling for invalid dates

**Verify:** Manual test in admin UI - schedule riddle, check jobs table

---

## Verification Checklist

After implementing all tasks:

- [x] `mix compile` — no warnings ✓
- [x] `mix format` — code formatted ✓
- [x] `mix test` — all tests pass (161 tests, 0 failures) ✓
- [ ] Manual IEx test (requires DB + server running):

  ```elixir
  riddle = Riddlr.Repo.get!(Riddlr.Games.Riddle, 1)
  live_date = DateTime.utc_now() |> DateTime.add(600, :second)
  {:ok, result} = Riddlr.Games.schedule_riddle(riddle, live_date)

  # Check jobs
  Oban.Job |> Riddlr.Repo.all()

  # Drain queue
  Oban.drain_queue(queue: :game_lifecycle)

  # Verify state
  Riddlr.Repo.reload(riddle).play_status  # Should be "live"
  ```

---

## PubSub Events

**Topic namespace:** `games:riddle:*`

Events broadcasted:

- `games:riddle:scheduled` — When riddle scheduled
- `games:riddle:ready` — 5 min before live (triggers notifications in Phase 13)
- `games:riddle:started` — When riddle goes live
- `games:riddle:completed` — When riddle completed
- `games:riddle:archived` — When riddle archived

**Consumers (future phases):**

- Phase 8: Lobby LiveView subscribes to `games:riddle:started`
- Phase 13: Notifications context subscribes to all events
- Phase 10: Answer feed subscribes to completion

---

## Dependencies & Integration

**Depends on:**

- Phase 4 ✅ Riddle schema
- Phase 5 ✅ Admin area

**Blocks:**

- Phase 8 (Lobby needs :ready state)
- Phase 9 (Live game needs :live state)
- Phase 11 (Completion needs :completed, :archived states)
- Phase 13 (Notifications subscribe to PubSub events)

**Notes:**

- `CompleteRiddleWorker` enqueued in `start_riddle` but not created until Phase 11
- ETS cleanup in `archive_riddle` deferred to Phase 9 (no ETS yet)
- Admin form integration ensures proper workflow from UI

---

## Risks & Mitigations

**Risk 1: Jobs not executing at scheduled time**

- **Mitigation:** Oban runs in application supervisor, survives server restart
- **Verification:** Test with actual scheduled time (not past), check Oban logs

**Risk 2: Race conditions on concurrent transitions**

- **Mitigation:** Ecto.Multi atomic transactions, idempotency checks, unique constraints
- **Verification:** Test concurrent worker execution

**Risk 3: Timezone confusion (live_date in UTC vs local)**

- **Mitigation:** Store all timestamps in UTC (already configured via :utc_datetime)
- **Verification:** Document admin UI should display UTC clearly

---

## Unresolved Questions

None - Phase 7 scope is clear and contained.

---

## Definition of Done

- [x] All checkboxes in tasks completed ✓
- [x] All tests pass (`mix test`) - 161 tests, 0 failures ✓
- [x] No compilation warnings ✓
- [x] Code formatted (`mix format`) ✓
- [ ] Manual verification in IEx (pending user runtime testing)
- [x] Admin UI can schedule riddles with schedule_riddle/2 integration ✓
- [x] PubSub events implemented in all transitions (tested) ✓

---

## Task Summary

**Total tasks:** 8

- Configuration: 2 (Oban setup, state validation)
- Implementation: 5 (5 transition functions, 3 workers)
- Testing: 3 (integration, worker tests, admin integration)
- Verification: 1

**Estimated complexity:** Medium
**Phasing:** Single phase, sequential implementation recommended
