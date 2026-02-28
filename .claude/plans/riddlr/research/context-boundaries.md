# Context Boundaries Analysis - Riddlr

## Recommended Context Structure

### Core Contexts

#### 1. Accounts
**Responsibility:** User identity, authentication, authorization, player profiles, bans

**Schemas:**
- `User` (player) - identity, stats, preferences, ban status

**Key Functions:**
```elixir
# Phoenix 1.8 pattern - scope as first param
def get_user(%Scope{} = scope, id)
def update_profile(%Scope{} = scope, user, attrs)
def ban_user(%Scope{} = scope, user_id, reason)
def list_players_for_leaderboard(%Scope{} = scope, period)
def increment_stats(%Scope{} = scope, user_id, stats_map)
```

**Stats Management:**
Player stats (`total_points`, `wins_count`, `podium_count`) live in User schema but are **updated by Games context via Accounts API**. No circular dependency - Games calls `Accounts.increment_stats/3`, passing scope and delta values.

**Owns:** User authentication, profile CRUD, ban logic, leaderboard queries

---

#### 2. Games
**Responsibility:** Riddle lifecycle, game state machine, answer validation, scoring, completion

**Schemas:**
- `Riddle` - riddle data, play_status state machine
- `Tag` - categorization
- `RiddleTag` - join table

**Key Functions:**
```elixir
def list_riddles(%Scope{} = scope, filters)
def create_riddle(%Scope{} = scope, attrs)
def schedule_riddle(%Scope{} = scope, riddle_id, live_date)
def transition_to_ready(%Scope{} = scope, riddle_id)
def start_riddle(%Scope{} = scope, riddle_id)
def complete_riddle(%Scope{} = scope, riddle_id)
def archive_riddle(%Scope{} = scope, riddle_id)
def validate_answer(%Scope{} = scope, riddle, answer_text)
def calculate_placements(%Scope{} = scope, answer_feed)
def award_points(%Scope{} = scope, riddle_id, placements)
```

**State Machine:** Games context owns all play_status transitions (closed → scheduled → ready → live → completed → archived). Oban workers call Games functions for auto-transitions.

**Owns:** Riddle CRUD, state transitions, answer correctness validation, scoring logic

**Cross-boundary:** Calls `Accounts.increment_stats/3` to update player stats after game completion

---

#### 3. Gameplay
**Responsibility:** Real-time game session, answer feed, player connections, submission tracking

**Schemas:** None (ephemeral state in GenServer/ETS/LiveView assigns)

**Key Functions:**
```elixir
def join_game(%Scope{} = scope, riddle_id)
def submit_answer(%Scope{} = scope, riddle_id, answer_text)
def get_answer_feed(%Scope{} = scope, riddle_id)
def get_active_player_count(%Scope{} = scope, riddle_id)
def check_cooldown(%Scope{} = scope, riddle_id, user_id)
def track_submission(%Scope{} = scope, submission)
```

**Rationale for Separate Context:**
- Games = riddle management (admin concerns, CRUD, state machine)
- Gameplay = live session management (player concerns, real-time submissions, ephemeral state)
- Different scalability characteristics (Gameplay needs GenServer/ETS, Games uses Repo)
- Gameplay could theoretically be a separate service

**Owns:** Answer feed (in-memory), player connection tracking, cooldown enforcement, real-time PubSub broadcasts

**Cross-boundary:** Calls `Games.validate_answer/3` to check correctness, calls `Games.complete_riddle/2` when game ends

---

#### 4. Moderation
**Responsibility:** Content filtering, flagging, admin actions

**Schemas:**
- `FlaggedAnswer` - flagged submission records (optional for Phase 15)

**Key Functions:**
```elixir
def check_content(%Scope{} = scope, text)
def flag_answer(%Scope{} = scope, answer_id, reason)
def hide_answer(%Scope{} = scope, answer_id)
def list_flagged_content(%Scope{} = scope, filters)
```

**Rationale for Separate Context:**
- Moderation is a bounded domain (filtering, flagging, review workflow)
- Will expand in Phase 2 (AI moderation, appeal system)
- Admins/moderators own this domain

**Owns:** Content validation, flagging logic, moderation dashboard queries

**Cross-boundary:** Called by Gameplay before broadcasting answers

---

#### 5. Notifications
**Responsibility:** Email/SMS delivery, notification preferences, templates

**Schemas:**
- `NotificationLog` (optional, for audit trail)

**Key Functions:**
```elixir
def send_game_scheduled(%Scope{} = scope, riddle, recipients)
def send_game_starting(%Scope{} = scope, riddle, recipients)
def send_game_results(%Scope{} = scope, riddle, recipients)
def get_opted_in_users(%Scope{} = scope, riddle_id, channel)
```

**Rationale for Separate Context:**
- Notifications are a distinct technical concern
- Integrates external services (Swoosh, Twilio)
- Can be tested/mocked independently

**Owns:** Email/SMS delivery, preference checking, template rendering

**Cross-boundary:** Games context broadcasts PubSub events (`riddle:scheduled`, `riddle:completed`), Notifications subscribes and sends

---

### Alternative Considered (Simpler Structure)

**Games + Gameplay merged into single Games context:**
- Pros: Fewer files, simpler for small team
- Cons: God context (800+ lines), mixes admin/player concerns, harder to test

**Decision:** Keep separate. Riddlr's real-time gameplay is core value prop, deserves dedicated context.

---

## Context Interaction Diagram

```
┌─────────────┐
│  Accounts   │───────────────────────────────┐
│             │                               │
│ User schema │                               │
│ Stats CRUD  │                               │
└─────────────┘                               │
       ▲                                      │
       │ increment_stats/3                    │
       │                                      │
┌─────────────┐          ┌─────────────┐     │
│   Games     │◄─────────│  Gameplay   │     │
│             │ validate │             │     │
│ Riddle CRUD │  answer  │ Answer feed │     │
│ State       │          │ PubSub      │     │
│ machine     │          │ Cooldowns   │     │
└─────────────┘          └─────────────┘     │
       │                        │             │
       │ PubSub events          │ check       │
       │                        │ content     │
       ▼                        ▼             │
┌─────────────┐          ┌─────────────┐     │
│Notifications│          │ Moderation  │     │
│             │          │             │     │
│ Email/SMS   │          │ Flagging    │     │
└─────────────┘          └─────────────┘     │
       │                                      │
       └──────────────────────────────────────┘
              get_opted_in_users/3
```

---

## Leaderboard Context Decision

**Question:** Where do leaderboards live?

**Answer:** **Accounts context**

**Rationale:**
- Leaderboards query User schema (total_points, wins_count)
- Accounts already owns player stats
- `Accounts.list_players_for_leaderboard/2` is a natural query function
- No new schemas needed (just different query filters)

**Alternative Considered:** Separate Leaderboards context
- Overkill for MVP (just query functions, no unique schemas)
- Would create thin wrapper around Accounts queries
- Defer until Phase 2 if leaderboard logic becomes complex (category-specific, caching layer, etc.)

---

## Tag System Context Decision

**Question:** Tags in Games or separate Tags context?

**Answer:** **Games context**

**Rationale:**
- Tags exist only to categorize riddles (no other use case)
- Tag CRUD is admin function, managed alongside riddles
- Tag schema is simple (id, name)
- If tags become reusable across other entities (future: tag players, tag achievements), extract to Tags context in Phase 2

---

## Admin/Moderation Context Decision

**Question:** Admin tools in Accounts or separate Admin context?

**Answer:** **Split by domain, not by role**

- User bans → `Accounts.ban_user/3`
- Riddle CRUD → `Games.create_riddle/2`
- Content moderation → `Moderation.flag_answer/3`

**Rationale:**
- Admin is a **role**, not a **domain**
- Contexts should model business domains, not user types
- Authorization happens at controller/LiveView layer (plugs check role)
- Each context function accepts `%Scope{}` with user/role info

**Admin-specific UI:**
- `lib/riddlr_web/live/admin/` directory for admin LiveViews
- Each LiveView delegates to appropriate context based on domain

---

## PubSub Topic Structure

Organized by context and resource:

```elixir
# Games context
"games:riddle:#{riddle_id}:state_changed"
"games:riddle:#{riddle_id}:archived"

# Gameplay context
"gameplay:#{riddle_id}:answer_submitted"
"gameplay:#{riddle_id}:player_joined"
"gameplay:#{riddle_id}:player_count"
"gameplay:lobby:#{riddle_id}"

# Leaderboards (Accounts context)
"accounts:leaderboard:updated"

# Moderation context
"moderation:answer:flagged"
```

**Pattern:** `context:resource:id:event` for namespacing

---

## Circular Dependency Prevention

**Problem:** User stats tracked in Accounts, updated by Games after completion. Circular?

**Solution:** **One-way dependency**

```elixir
# Games context
def complete_riddle(%Scope{} = scope, riddle_id) do
  Ecto.Multi.new()
  |> Multi.update(:riddle, complete_changeset(riddle))
  |> Multi.run(:placements, fn _, %{riddle: riddle} ->
    calculate_placements(scope, riddle)
  end)
  |> Multi.run(:update_stats, fn _, %{placements: placements} ->
    Enum.each(placements, fn {user_id, points, placement} ->
      stats = %{
        total_points: points,
        wins_count: if(placement == 1, do: 1, else: 0),
        podium_count: if(placement <= 3, do: 1, else: 0),
        games_played: 1
      }
      Accounts.increment_stats(scope, user_id, stats)
    end)
    {:ok, :stats_updated}
  end)
  |> Repo.transaction()
  |> broadcast(scope, :completed)
end
```

**Key:**
- Games depends on Accounts (calls `increment_stats/3`)
- Accounts never calls Games
- Direction: Games → Accounts (one-way)

---

## Testing Strategy by Context

### Accounts
- Context functions (unit)
- Changeset validation
- Authorization logic
- Leaderboard queries

### Games
- State machine transitions (unit)
- Invalid transition errors
- Answer validation (case-insensitivity, trimming)
- Scoring logic

### Gameplay
- Answer submission (integration with GenServer)
- Cooldown enforcement
- PubSub broadcasts
- Player count tracking

### Moderation
- Content filtering (mock API)
- Flagging workflow

### Notifications
- Email/SMS delivery (Swoosh.TestAssertions)
- Preference respect
- Template rendering

---

## Anti-patterns to Avoid

### DO NOT
- Query User schema directly from Gameplay LiveView → use `Accounts.get_user/2`
- Query Riddle schema from Accounts context → pass `riddle_id`, not full schema
- Put real-time game logic in Games context → belongs in Gameplay
- Create `Services/` directory → use contexts
- Put business logic in LiveViews → thin views, fat contexts

### DO
- Accept `%Scope{}` as first param in all public context functions
- Use `Ecto.Multi` for transactions with side effects (stats updates, broadcasts)
- PubSub broadcasts in contexts, subscriptions in LiveViews
- Return tagged tuples `{:ok, _}` / `{:error, _}` for pipeline-friendly APIs

---

## File Structure (Post-Implementation)

```
lib/riddlr/
├── accounts/
│   ├── user.ex
│   └── scope.ex
├── accounts.ex
├── games/
│   ├── riddle.ex
│   ├── tag.ex
│   └── riddle_tag.ex
├── games.ex
├── gameplay/
│   ├── session.ex (GenServer)
│   └── answer_feed.ex
├── gameplay.ex
├── moderation/
│   └── flagged_answer.ex
├── moderation.ex
├── notifications.ex
└── repo.ex

lib/riddlr_web/
├── live/
│   ├── game_live/
│   │   ├── lobby.ex
│   │   └── play.ex
│   ├── admin/
│   │   ├── riddle_live/
│   │   │   ├── index.ex
│   │   │   ├── form.ex
│   │   │   └── show.ex
│   │   └── moderation_live/
│   │       └── index.ex
│   └── leaderboard_live.ex
├── controllers/
│   └── ...
└── plugs/
    ├── require_admin.ex
    └── require_authenticated.ex
```

---

## Phoenix 1.8 Patterns to Follow

### Scopes (MANDATORY)
```elixir
# Define scope struct
defmodule Riddlr.Accounts.Scope do
  defstruct [:user, :role, :is_admin, :session_id]
end

# Every context function accepts scope
def create_riddle(%Scope{is_admin: true} = scope, attrs) do
  # ...
end
```

### Verified Routes
Use `~p` sigil, not path helpers:
```elixir
# Good
<.link navigate={~p"/game/#{@riddle.id}/play"}>Play</.link>

# Old (pre-1.7)
<.link navigate={Routes.game_path(@socket, :play, @riddle.id)}>Play</.link>
```

### FallbackController for APIs
```elixir
# In controller
action_fallback RiddlrWeb.FallbackController

def show(conn, %{"id" => id}) do
  with {:ok, riddle} <- Games.get_riddle(conn.assigns.scope, id) do
    render(conn, "show.json", riddle: riddle)
  end
end
```

---

## Unresolved Questions

1. **Submission schema for Phase 2?** No persistent submissions in MVP (answer feed is ephemeral). If analytics needed, add `Gameplay.Submission` schema later.

2. **Gameplay session recovery?** If server restarts during live game, GenServer state lost. Persist critical state in DB or accept degraded experience?

3. **Leaderboard caching?** For high traffic, cache leaderboard queries (Cachex, ETS). Defer until load testing?

4. **Multi-tenancy?** Current design assumes single tenant. If white-label future (each org has own Riddlr instance), add `tenant_id` to all schemas and scope queries.

5. **Private games scope?** Private games (Phase 2 backlog) may need separate authorization layer. Add `visibility` enum to Riddle, filter in `Games.list_riddles/2`?

---

## Next Steps

1. Bootstrap project (`mix phx.new riddlr`)
2. Generate Accounts context (`mix phx.gen.auth`)
3. Add scope struct to `lib/riddlr/accounts/scope.ex`
4. Create Games context with Riddle schema
5. Implement state machine in Games context
6. Create Gameplay context with GenServer
7. Build LiveViews (thin controllers, delegate to contexts)
