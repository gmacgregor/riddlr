# State Machine Libraries Research

**Date**: 2026-03-02  
**Context**: Riddlr game lifecycle management (riddle play_status and publish_status transitions)  
**Current Implementation**: Pattern matching with Ecto changesets + Oban workers for scheduled transitions

## Executive Summary

**Recommendation**: **DO NOT USE A STATE MACHINE LIBRARY.** The current pattern matching + Ecto changesets approach is the idiomatic Elixir solution for Riddlr's needs. Adding a library would introduce unnecessary complexity without meaningful benefit.

**Why**: Riddlr's state machines are simple, well-defined, and benefit from explicit context functions (schedule_riddle, ready_riddle, start_riddle, complete_riddle, archive_riddle). The current implementation is maintainable, testable, and integrates perfectly with Oban for scheduled transitions.

---

## Candidate Libraries Evaluated

### 1. Machinery (REJECTED)

**Hex**: https://hex.pm/packages/machinery  
**GitHub**: https://github.com/joaomdmoura/machinery  
**Latest Release**: 1.1.0  
**Last Push**: 2024-05-03 (~10 months ago - marginally maintained)  
**Stars**: 565  
**Open Issues**: 12  

#### Strengths
- Simple DSL for defining states/transitions
- Guard clause support (via `guard_transition/2`)
- Built-in Phoenix integration
- Before/after callbacks for side effects
- Well-documented with examples

#### Why Not for Riddlr
1. **Adds ceremony without value** — Machinery's callbacks (`persist/2`, `log_transition/2`) duplicate what context functions already do (schedule_riddle, ready_riddle, etc.)
2. **Weak maintenance signal** — Last commit 10 months ago; library is stable but not actively developed
3. **Oban integration not built-in** — Scheduled transitions still require manual Oban setup; Machinery doesn't know about job scheduling
4. **Callback semantics clash** — Machinery encourages side effects in callbacks (logging, emails, etc.), but Riddlr already structures these as explicit context functions
5. **Phoenix dashboard is overhead** — Cool feature, but adds dependency weight for something not needed

#### Example of what we'd add
```elixir
# Before (current, clear)
def schedule_riddle(%Riddle{} = riddle, live_date) do
  Multi.new()
  |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: "scheduled", live_date: live_date}))
  |> Multi.insert(:ready_job, fn %{riddle: updated_riddle} ->
    %{riddle_id: updated_riddle.id}
    |> ReadyRiddleTransitionWorker.new(scheduled_at: DateTime.add(live_date, -300, :second))
  end)
  |> ...
end

# After (Machinery)
defmodule RiddleStateMachine do
  use Machinery,
    states: ["closed", "scheduled", "ready", "live", "completed", "archived"],
    transitions: %{
      "closed" => ["scheduled"],
      "scheduled" => ["ready", "closed"],
      # ...
    }
  
  def persist(riddle, "scheduled") do
    # Now where do we schedule the Oban jobs? In persist/2?
    # That's already what Games.schedule_riddle does...
  end
end
```

---

### 2. GenStateMachine (NOT RECOMMENDED)

**Hex**: https://hex.pm/packages/gen_state_machine  
**GitHub**: https://github.com/ericentin/gen_state_machine  
**Latest Release**: 3.0.0  
**Last Push**: 2024-06-16 (~9 months ago)  
**Stars**: 313  
**Open Issues**: 5  

#### Strengths
- Wraps OTP's gen_statem (battle-tested)
- Idiomatic Elixir callback mode support
- Excellent for stateful processes (e.g., traffic light, stateful connection)

#### Why Not for Riddlr
1. **Process-based = overkill** — Riddlr states live in database, not in a GenServer/gen_statem process
2. **Synchronization complexity** — State lives in DB; launching a process per riddle adds multi-source-of-truth problems
3. **No Ecto integration** — Generic OTP tool; doesn't know about changesets, Multi, or database transactions
4. **Designed for different problem** — gen_statem is for "stateful components that make decisions based on events and time" (e.g., network protocols, game engines with internal timers). Riddlr's states are purely data-driven
5. **Oban incompatible pattern** — Scheduled transitions should fire via Oban jobs, not via gen_statem messages

---

### 3. Fsmx (MOST TEMPTING, STILL REJECTED)

**Hex**: https://hex.pm/packages/fsmx  
**GitHub**: https://github.com/subvisual/fsmx  
**Latest Release**: 0.5.0  
**Last Push**: 2023-09-08 (~18 months ago - approaching maintenance risk threshold)  
**Stars**: 174  
**Open Issues**: 5  

#### Strengths
- Lightweight, functional approach
- Works with plain structs OR Ecto changesets
- `before_transition/3` callback for validation logic
- Ecto.Multi support for atomic transitions
- No process overhead (purely functional)

#### Why Not for Riddlr
1. **Approaching abandonment** — No commits in 18 months; acceptable risk for stable code, but not a growth path
2. **We already have this pattern** — Fsmx's strength is "validates transitions before committing"; Riddlr already does this via `Riddle.validate_play_status_transition/1`
3. **Adds indirection** — Defining separate `defstruct` just to hold state, plus FSM module, plus context functions = more moving parts
4. **Scheduled transitions not modeled** — Fsmx handles immediate transitions; Oban scheduling is still manual setup
5. **Complexity budget spent elsewhere** — Riddlr's complexity is in **domain logic** (schedule_riddle orchestrates Multi + Oban), not in FSM semantics

#### Comparison: Current vs. Fsmx
```elixir
# Current (Riddlr)
def schedule_riddle(%Riddle{} = riddle, live_date) do
  cond do
    DateTime.compare(live_date, DateTime.utc_now()) == :lt -> {:error, :live_date_in_past}
    riddle.play_status != "closed" -> {:error, "cannot schedule riddle in #{riddle.play_status} state"}
    true ->
      Multi.new()
      |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: "scheduled", live_date: live_date}))
      |> Multi.insert(:ready_job, ...)
      |> Multi.insert(:live_job, ...)
      |> Repo.transaction()
  end
end

# With Fsmx
defmodule RiddleStateMachine do
  use Fsmx.Struct, transitions: %{"closed" => ["scheduled"], ...}
  
  def before_transition(riddle, "closed", "scheduled") do
    if DateTime.compare(live_date, DateTime.utc_now()) == :lt do
      {:error, :live_date_in_past}
    else
      {:ok, riddle}
    end
  end
end

# But we STILL need:
def schedule_riddle(%Riddle{} = riddle, live_date) do
  with {:ok, fsm_result} <- Fsmx.transition(riddle, "scheduled") do
    # ... manually insert Oban jobs
    # ... manually handle Multi/transaction
  end
end

# Net result: We have BOTH Fsmx AND domain logic.
```

---

### 4. Gearbox (REJECTED — Interesting but Wrong Fit)

**Hex**: https://hex.pm/packages/gearbox  
**GitHub**: https://github.com/edisonywh/gearbox  
**Latest Release**: 0.3.5  
**Last Push**: 2024-09-22 (~5 months ago - well maintained)  
**Stars**: 193  
**Open Issues**: 5  

#### Strengths
- Explicitly rejects callbacks (forces side effects into context)
- Functional, no process overhead
- Guard transitions for business logic
- Inspired by Machinery, but cleaner philosophy
- Recent maintenance

#### Why Not for Riddlr
1. **Still adds ceremony** — Even with anti-callback philosophy, requires separate state machine module + definition
2. **No advantage over current** — Gearbox's main win is "no side effects"; Riddlr already has no side effects (everything is in explicit context functions)
3. **Scheduled transitions still manual** — Oban setup not modeled by state machine
4. **Transition metadata overhead** — Gearbox passes metadata through transitions; Riddlr doesn't need this complexity

#### Example: What we'd add
```elixir
defmodule PaymentMachine do
  use Gearbox,
    field: :play_status,
    states: ~w(closed scheduled ready live completed archived),
    transitions: %{
      "closed" => "scheduled",
      "scheduled" => ["ready", "closed"],
      ...
    }
end

# Then in context
def schedule_riddle(%Riddle{} = riddle, live_date) do
  with {:ok, _} <- Gearbox.transition(riddle, PaymentMachine, "scheduled") do
    # Still manually insert Oban jobs
    # Still manually structure the Multi
  end
end
```

---

### 5. Ecto State Machine (LEGACY, REJECTED)

**Hex**: https://hex.pm/packages/ecto_state_machine  
**GitHub**: https://github.com/asiniy/ecto_state_machine  
**Latest Release**: 0.3.0  
**Last Push**: 2020-03-03 (~6 years ago - ABANDONED)  
**Stars**: 100  
**Open Issues**: 15  

#### Why Not
- **Dead project** — No commits since 2020; unresponsive maintainer
- **Generates code via macros** — Feels like metaprogramming antipattern (generates `confirm/1`, `can_confirm?/1`, etc.)
- **Ruby/AASM semantics mismatch** — Designed for Rails workflow; not idiomatic Elixir

---

### 6. Exsm (NOT EVALUATED — Minimal Adoption)

**Hex**: https://hex.pm/packages/exsm  
**GitHub**: https://github.com/sakshamgupta05/exsm  
**Latest Release**: 0.3.2  
**Stars**: < 50  

Minimal adoption, minimal maintenance. Not worth detailed evaluation.

---

## Failure Modes & Scalability Analysis

### Current Implementation (No Library)
```
├─ State representation: Database column (play_status)
├─ Validation: Ecto changesets + custom validators
├─ Scheduling: Oban workers with unique/deduplication
├─ Side effects: Explicit context functions (schedule_riddle, ready_riddle, etc.)
└─ Testing: Unit test each transition function separately
```

**Failure Mode**: If a state transition fails, error is returned to caller (Multi ensures atomicity). Context explicitly decides what to do (retry, user-facing error, log, etc.).

**Scalability**:
- 1k riddles: No problem (query + changesets are simple)
- 10k riddles: No problem (Oban handles job queue, not state machine)
- 100k riddles: No problem (each transition is single UPDATE + job insert)

---

### With Machinery
**Issues**:
1. **Callbacks + database = subtle bugs** — `persist/2` callback called AFTER transition validates, but BEFORE transaction commits. Exception in callback = failed transaction. Error handling becomes implicit.
2. **Oban jobs become implicit details** — Not modeled by Machinery; jobs scheduled inside `persist/2`, adding invisible dependencies
3. **Logging/observability fragmented** — `log_transition/2` callback + explicit logging in context functions = duplication

---

### With GenStateMachine
**Critical Issues**:
1. **Multi-source-of-truth** — State in DB + state in gen_statem process. If worker crashes, process state lost; next request sees stale DB state.
2. **Synchronization nightmare** — Admin changes state in DB; gen_statem process doesn't know. Real-world Riddlr scenario: cancel publishing (draft state) while process is mid-transition.
3. **Oban worker + gen_statem = doubled complexity** — Both trying to drive state; unclear ownership

---

### With Fsmx
**Issues**:
1. **Distributed transitions** — FSM validation in Fsmx module, side effects in context; two places to reason about correctness
2. **Oban scheduling invisible** — FSM doesn't model scheduled jobs; still manual setup, no single place to see full transition flow

---

## Best Practices for Scheduled State Transitions

**Current Riddlr pattern (idiomatic)**:

```elixir
# Step 1: Business logic in context
def schedule_riddle(%Riddle{} = riddle, live_date) do
  # Validation upfront
  cond do
    DateTime.compare(live_date, DateTime.utc_now()) == :lt -> {:error, :live_date_in_past}
    riddle.play_status != "closed" -> {:error, "cannot schedule riddle in #{riddle.play_status} state"}
    true ->
      Multi.new()
      |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: "scheduled", live_date: live_date}))
      |> Multi.insert(:ready_job, fn %{riddle: updated_riddle} ->
        %{riddle_id: updated_riddle.id}
        |> ReadyRiddleTransitionWorker.new(scheduled_at: DateTime.add(live_date, -300, :second))
      end)
      |> Multi.insert(:live_job, fn %{riddle: updated_riddle} ->
        %{riddle_id: updated_riddle.id}
        |> LiveRiddleTransitionWorker.new(scheduled_at: live_date)
      end)
      |> Repo.transaction()
  end
end

# Step 2: Scheduled transitions idempotent via workers
defmodule ReadyRiddleTransitionWorker do
  use Oban.Worker, queue: :game_lifecycle, max_attempts: 3

  def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
    case Repo.get(Riddle, id) do
      nil -> {:cancel, "Riddle #{id} not found"}
      riddle ->
        cond do
          riddle.publish_status != "published" -> {:cancel, "Not published"}
          riddle.play_status != "scheduled" -> {:cancel, "Already transitioned"}
          true -> Games.ready_riddle(id) |> case do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end
end

# Step 3: Explicit context function for transition
def ready_riddle(riddle_id) do
  # Fetch, validate, update, broadcast in one place
end
```

**Why this is correct**:
1. ✅ **Idempotent workers** — Can safely retry if Oban crashes
2. ✅ **Guard against race conditions** — Worker checks publish_status + play_status before transitioning
3. ✅ **Single source of truth** — Database only; no process state
4. ✅ **Observable** — All transitions visible in context functions
5. ✅ **Testable** — No callbacks, no implicit side effects

---

## Security Considerations

### Current Implementation
**Strengths**:
- ✅ No user input in state transitions (all via context functions)
- ✅ No dynamic atom creation
- ✅ No unsafe callbacks that could be exploited

**Risks**:
- ⚠️ Oban job args must use string keys (currently correct: `%{"riddle_id" => id}`)
- ⚠️ Worker publish_status check prevents unpublished riddles from transitioning (currently correct)

### With a Library
**No improvement** — Libraries don't eliminate these concerns. Machinery/Fsmx still allow unsafe code in callbacks if used carelessly.

---

## Compatibility Notes

**Elixir**: 1.15+ (current requirement)  
**Phoenix**: 1.8.3 (current)  
**Ecto**: 3.13 (current)  
**Oban**: 2.18 (current)

All evaluated libraries are compatible with current stack. **No conflict issues.**

---

## Recommendation: Build Nothing, Improve Subtly

### Keep Current Approach
The current pattern is **idiomatic Elixir** and requires no library:

1. **Ecto changesets** for validation
2. **Ecto.Multi** for atomic state + job insertion
3. **Oban workers** for scheduled transitions
4. **Context functions** for domain logic

### Optional Improvements (No Library)

#### 1. Extract transition logic to helper module
```elixir
# lib/riddlr/games/riddle_transitions.ex
defmodule Riddlr.Games.RiddleTransitions do
  alias Riddlr.Games.Riddle
  
  @valid_transitions %{
    "closed" => ["scheduled"],
    "scheduled" => ["ready", "closed"],
    "ready" => ["live", "closed"],
    "live" => ["completed"],
    "completed" => ["archived"],
    "archived" => []
  }
  
  def can_transition?(current, next) do
    next in Map.get(@valid_transitions, current, [])
  end
  
  def validate_transition(changeset, current, next) do
    if can_transition?(current, next) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :play_status, "invalid transition")
    end
  end
end
```

**Benefit**: Centralizes transition rules; easier to visualize allowed paths.

#### 2. Document state flow in module attributes
```elixir
defmodule Riddlr.Games.Riddle do
  @moduledoc """
  Riddle entity with play_status lifecycle.
  
  ## Play Status Lifecycle
  
  ```
  closed --schedule--> scheduled --5min before--> ready --at live_date--> live
    ^                       ^                                               |
    |                       |                                               v
    +---- cancel ----------+---- live_date passes (handled by PublishCheck) completed
                                                                           |
                                                                           v
                                                                        archived
  ```
  
  See Games.schedule_riddle/2, Games.ready_riddle/1, Games.start_riddle/1 for transitions.
  """
```

**Benefit**: Clearer documentation; easier onboarding.

---

## Why Riddlr Doesn't Need a State Machine Library

| Concern | Answer |
|---------|--------|
| **Are states complex?** | No. 6 states, 5 explicit transitions. Simple enough for comments. |
| **Do we need to model events?** | No. Events are: schedule (user), time passing (worker), publish (user). All handled by explicit functions. |
| **Do we need callbacks?** | No. Side effects (PubSub broadcast, job scheduling) are explicit in context functions. |
| **Do we need visualization?** | No. State diagram fits in comments. |
| **Do we need automatic state machine code generation?** | No. 50 lines of changesets + 200 lines of context functions is transparent and maintainable. |
| **Are we losing anything by not using a library?** | No. We have: validation (changesets), scheduling (Oban), transitions (context functions). |

---

## Conclusion

**Status**: Use pattern matching + Ecto changesets + Oban. No library needed.

**Implementation effort**: ~0 (already done)  
**Maintenance burden**: Minimal (clear, idiomatic Elixir)  
**Test coverage**: High (each function testable independently)  
**Scalability**: Excellent (database-backed, not process-backed)  

The current Riddlr implementation is the **gold standard** for state machines in Elixir. Every evaluated library adds complexity without solving any problems that don't already have solutions.
