# Riddlr Implementation Plan (Enhanced)

## Context

Real-time multiplayer riddle game. Admins create riddles, players compete to solve first. Scoring: 10/7/3 pts for 1st/2nd/3rd. Greenfield Phoenix project—only spec docs exist currently.

## Architecture Decisions

### Context Boundaries

**5 core contexts:**

- **Accounts** - User auth, profiles, stats (total_points, wins_count), leaderboard queries
- **Games** - Riddle lifecycle, state machine, CRUD, tags, answer validation
- **Gameplay** - Ephemeral game state (answer feed, cooldowns, player connections)
- **Moderation** - Content filtering, flagging, external API integration
- **Notifications** - Email/SMS delivery via PubSub subscription to game events

**Key patterns:**

- One-way flow: Games → `Accounts.increment_stats/3` (prevents circular deps)
- Tags live in Games (not separate context until reusability needed)
- No Admin context (role-based authorization, not domain)
- PubSub topics: `context:resource:id:event` (e.g., `gameplay:123:answer_submitted`)

### Answer Storage Architecture

**Decision: ETS over GenServer**

- `:bag` table with composite key `{riddle_id, user_id}`
- `:read_concurrency` + `:write_concurrency` for 100+ concurrent submissions
- No GenServer needed - pure concurrent data structure
- Cleanup via `match_delete` on archive (no process lifecycle)
- Table name: `:riddle_answers`

### LiveView Patterns

- **Countdown:** Hybrid (server tick 1s, JS hook updates 100ms for smooth UX)
- **Player count:** Phoenix Presence (assigns, not streams - small data)
- **Answer feed:** Streams with `at: 0, limit: 100` (prevents memory explosion)
- **Answer submission:** `assign_async` for validation (content moderation = async)
- **Cooldown:** Server-enforced via ETS atomic check-and-set

### Oban Workers

**Separate workers per transition type:**

- `ReadyRiddleTransitionWorker` - scheduled → ready (5 min before live_date)
- `LiveRiddleTransitionWorker` - ready → live (exact live_date)
- `ArchiveRiddleTransitionWorker` - completed → archived (+3 min)

**Idempotency:** Check `play_status` before transition, return `{:cancel, reason}` if already transitioned
**Queue:** `:game_lifecycle` (limit: 5), separate from `:mailers` and `:default`
**Unique constraints:** `[period: {1, :hour}, keys: [:riddle_id], states: [:available, :scheduled]]`

### Security Patterns

- **Admin auth:** `on_mount` hooks (not controller plugs) - LiveView-first
- **Roles:** Hierarchical with flat permission map (`@role_permissions`)
- **Content moderation:** Async (display immediately, flag in background), fail-open on API errors
- **XSS:** Never use `raw/1` on player content (auto-escape only)
- **handle_event auth:** Re-verify ban status, game state, cooldown every event
- **Ban enforcement:** 3-layer (mount check + PubSub push + 5-min periodic verify)

## Critical Files (post-creation)

- `lib/riddlr/accounts.ex` — user management, stats updates, leaderboard queries
- `lib/riddlr/games.ex` — riddle CRUD, state machine, answer validation
- `lib/riddlr/gameplay.ex` — ephemeral answer storage, cooldown checks
- `lib/riddlr/moderation.ex` — content filtering (local + external API)
- `lib/riddlr/notifications.ex` — email/SMS delivery
- `lib/riddlr/authorization.ex` — role→permission mapping
- `lib/riddlr_web/live/game_live/play.ex` — live game interface
- `lib/riddlr_web/live/admin/riddle_live/index.ex` — admin riddle management
- `lib/riddlr/workers/ready_riddle_transition_worker.ex` — auto-ready transition
- `lib/riddlr/workers/live_riddle_transition_worker.ex` — auto-live transition
- `lib/riddlr/workers/archive_riddle_transition_worker.ex` — auto-archive

---

## Phase 1: Project Bootstrap

**Goal:** Working Phoenix app

**Deliverables:**

- `mix phx.new riddlr` (Phoenix 1.8)
- PostgreSQL configured
- Tailwind CSS
- Git init
- Oban dependency (`{:oban, "~> 2.18"}`)

**Tests:**

- `mix test` passes
- Server starts, home page renders

**Verify:** `mix ecto.create && mix test && mix phx.server`

---

## Phase 2: Authentication

**Goal:** User registration, login, sessions

**Deliverables:**

- `mix phx.gen.auth Accounts User users`
- Add `username` field (unique, required, index)
- Basic profile page

**Tests:**

- Registration with username
- Login/logout
- Session persistence
- Username uniqueness

**Verify:** Register, login, session persists across refresh

---

<!-- ## Phase 3: Enhanced Player Schema

**Goal:** Complete player profile with MVP fields

**Deliverables:**

- Migration: Add to User: `display_name`, `mobile_number`, `email_address`, `communication_preference`, `account_status` (default: `:active`), `total_points` (default: 0), `wins_count` (default: 0), `podium_count` (default: 0), `games_played` (default: 0), `current_streak` (default: 0), `longest_streak` (default: 0), `last_active_at`, `notification_settings` (map, default: `%{email: true, sms: false}`)
- Profile edit LiveView
- `Accounts.increment_stats/3` public API for Games context
- Index on `total_points` (leaderboards)

**Tests:**

- Changeset validation (all fields)
- Profile update
- Default values
- Notification settings map structure
- `increment_stats/3` (total_points, wins_count, etc.)

**Verify:** Edit profile, check DB values, test defaults, call `increment_stats` in IEx -->

---

## Phase 4: Riddle Schema & Contexts

**Goal:** Core riddle data structure + context split

**Deliverables:**

- **Games context** - Riddle schema: `name`, `description`, `answers` (array), `play_status` (enum: closed/scheduled/ready/live/completed/archived), `solve_time` (seconds), `category`, `difficulty`, `hint`, `hint_delay`, `live_date`, `publish_status`, `first_solver_id`, `first_solve_time`, `completion_rate`, `average_solve_time`
- **Gameplay context** (stub) - Will handle ephemeral state (Phase 9)
- CRUD functions: `create_riddle/1`, `list_riddles/0`, `get_riddle!/1`, `update_riddle/2`
- Seeds with sample riddles
- Index on `play_status` (frequent queries)

**Tests:**

- Changeset validation (answers array non-empty, enums, required fields)
- CRUD functions
- Enum validation (play_status, difficulty)
- Answers array validation (at least one answer)

**Verify:** `mix run priv/repo/seeds.exs`, check `Games.list_riddles()` in IEx

---

## Phase 5: Admin Area & Riddle Management

**Goal:** Admin-only CRUD UI with role-based auth

**Deliverables:**

- Migration: Add `role` to User (enum: super_admin/moderator/editor/viewer/player, default: `:player`)
- **Authorization module** (`lib/riddlr/authorization.ex`) - `@role_permissions` map, `has_permission?/2`, `authorize/3`
- **AdminAuth module** (`lib/riddlr_web/admin_auth.ex`) - `on_mount` hook with `:require_admin` and `{:require_role, roles}`
- Admin layout (`lib/riddlr_web/components/layouts/admin.html.heex`)
- Riddle LiveView: index (list all), form (create/edit), show (view one)
- Router: `live_session :admin` with `on_mount: [{RiddlrWeb.AdminAuth, :require_admin}]`

**Tests:**

- Authorization module (`has_permission?/2` for each role)
- Admin `on_mount` hook (redirects non-admin)
- LiveView mount (admin only, assigns `:current_admin`)
- Form submission (create/edit riddle)
- List rendering (riddles table)
- Non-admin redirect (player role → home)

**Verify:**

- Login as admin, navigate `/admin/riddles`, CRUD riddles
- Login as player, verify redirect from `/admin/riddles`
- Test role permissions (editor can create, viewer cannot)

---

<!-- ## Phase 6: Tag System
**Goal:** Tag management and riddle tagging

**Deliverables:**
- Tag schema (`name`, unique index lowercase)
- RiddleTag join schema (riddle_id, tag_id, composite unique)
- Tag autocomplete in riddle form (live search)
- Display tags on riddle show
- Tag CRUD in admin area

**Tests:**
- Tag creation (changeset validation)
- Uniqueness (case-insensitive: "Math" = "math")
- RiddleTag association (many-to-many)
- Multiple tags per riddle
- Autocomplete query (ILIKE search)

**Verify:** Create tags, assign to riddles, test autocomplete, verify case-insensitivity -->

---

## Phase 7: Game Lifecycle State Machine

**Goal:** Play status transitions with Oban auto-scheduling

**Deliverables:**

- **State transition functions:**
  - `schedule_riddle(riddle, live_date)` - closed → scheduled, enqueues Ready + Live jobs
  - `ready_riddle(riddle_id)` - scheduled → ready (called by Oban worker)
  - `start_riddle(riddle_id)` - ready → live (called by Oban worker)
  - `complete_riddle(riddle_id)` - live → completed, enqueues Archive job
  - `archive_riddle(riddle_id)` - completed → archived (called by Oban worker)
- **Oban workers:**
  - `ReadyRiddleTransitionWorker` - Scheduled at `live_date - 5 min`
  - `LiveRiddleTransitionWorker` - Scheduled at exact `live_date`
  - `ArchiveRiddleTransitionWorker` - Scheduled at `complete_time + 3 min`
- **Worker patterns:**
  - Idempotency: Check `play_status` before transition, `{:cancel, reason}` if already transitioned
  - Error handling: `{:cancel, reason}` for permanent failures (wrong state), `{:error, reason}` for transient (DB timeout)
  - Unique constraints: `[period: {1, :hour}, keys: [:riddle_id]]`
  - Queue: `:game_lifecycle` (limit: 5)
- Oban config in `application.ex` (queues: game_lifecycle: 5, mailers: 3, default: 5)
- State validation in Riddle changeset (prevent invalid transitions)

**Tests:**

- Each transition function (valid state → next state)
- Invalid transitions fail (e.g., closed → live)
- State machine flow (full cycle: closed → scheduled → ready → live → completed → archived)
- Worker idempotency (run twice, second cancels)
- Scheduled job execution (Oban.Testing with `:manual` mode, `drain_queue/1`)
- Auto-archive after 3 min (scheduled job)

**Verify:**

- `schedule_riddle` in IEx, check DB play_status, verify 2 jobs enqueued
- Trigger transitions, verify state changes
- Test invalid transition (e.g., `start_riddle` when :scheduled → error)
- Drain queue, verify auto-transitions execute

**Implementation notes:**

```elixir
# schedule_riddle/2 pattern
def schedule_riddle(riddle, live_date) do
  Multi.new()
  |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: :scheduled, live_date: live_date}))
  |> Multi.insert(:ready_job, fn _ ->
    %{riddle_id: riddle.id}
    |> ReadyRiddleTransitionWorker.new(scheduled_at: DateTime.add(live_date, -300, :second))
  end)
  |> Multi.insert(:live_job, fn _ ->
    %{riddle_id: riddle.id}
    |> LiveRiddleTransitionWorker.new(scheduled_at: live_date)
  end)
  |> Repo.transaction()
end

# Worker idempotency pattern
def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
  riddle = Repo.get!(Riddle, id)
  if riddle.play_status == :scheduled do
    ready_riddle(id)
  else
    {:cancel, "Already transitioned (current: #{riddle.play_status})"}
  end
end
```

---

## Phase 8: Game Lobby (Ready State)

**Goal:** Pre-game countdown, player list with Presence

**Deliverables:**

- Lobby LiveView (`/game/:id/lobby`)
- **Countdown:** Hybrid pattern
  - Server: `:timer.send_interval(1000)` sends `:tick` with authoritative time remaining
  - Client: JS hook updates display every 100ms for smooth countdown
  - Single source of truth: `riddle.live_date`
- **Player count:** Phoenix Presence tracking
  - Track players in Presence (`Riddlr.Gameplay.Presence`)
  - Store in assigns (not streams - small data <100 players)
  - Display count, optional list of usernames
- Display category, difficulty, riddle name (not question yet)
- Auto-redirect to `/game/:id/play` when play_status → :live (via PubSub)
- Optional: "Ready" button (defer to Phase 17 backlog)

**Tests:**

- Lobby mount (only accessible when :ready, redirect if :closed/:scheduled)
- Countdown timer (tick every 1s, display updates)
- Player count Presence (join/leave tracked, count updates)
- PubSub subscription (`gameplay:lobby:#{id}`)
- Redirect to game when :live (broadcast transition)

**Verify:**

- Schedule riddle (live_date +2 min), navigate `/game/:id/lobby`
- Open multiple browser tabs, verify player count increments
- Watch countdown reach zero
- Verify auto-redirect when game goes :live

**Implementation notes:**

```elixir
# Presence tracking
def mount(%{"id" => id}, _session, socket) do
  if connected?(socket) do
    Presence.track(self(), "game:lobby:#{id}", socket.assigns.current_user.id, %{
      username: socket.assigns.current_user.username
    })
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:lobby:#{id}")
  end
  {:ok, assign(socket, player_count: get_presence_count(id))}
end

# Countdown tick
def handle_info(:tick, socket) do
  time_remaining = DateTime.diff(socket.assigns.riddle.live_date, DateTime.utc_now())
  if time_remaining <= 0 do
    # Auto-redirect handled by PubSub when state → :live
    {:noreply, socket}
  else
    {:noreply, push_event(socket, "countdown-tick", %{seconds: time_remaining})}
  end
end
```

---

## Phase 9: Live Game - Answer Submission

**Goal:** Core gameplay loop with ETS storage

**Deliverables:**

- Live game LiveView (`/game/:id/play`)
- Display riddle question, category, difficulty
- Text input for answers (form with phx-submit)
- **Answer validation:** `assign_async` pattern for async content check
  - Case-insensitive, trimmed comparison
  - Exact match against riddle.answers array
  - Content moderation may be async (200-500ms)
- **1-sec cooldown:** Server-enforced via ETS
  - ETS table `:answer_cooldowns` (`{user_id, riddle_id} → last_submit_timestamp`)
  - Atomic check-and-set pattern
  - Client-side button disable (UX only, not security)
- **Answer storage:** ETS (not GenServer)
  - Table: `:riddle_answers` (`:bag`, `:public`, `:read_concurrency`, `:write_concurrency`)
  - Key: `{riddle_id, user_id}`
  - Value: `{answer_text, timestamp_microseconds, correct?}`
  - Created in Application.start/2
- **Security checks in handle_event:**
  - Re-verify user not banned (`Accounts.get_user!/1`, check account_status)
  - Check game is :live
  - Check user hasn't already solved (query ETS for correct answer)
  - Check cooldown (ETS lookup, compare timestamp)
  - Validate input (length < 500, non-empty)
- Calculate placement (1st/2nd/3rd based on timestamp, microsecond precision)
- Award points: 1st=10, 2nd=7, 3rd=3, 4th+=0
- Update user stats via `Accounts.increment_stats/3`
- PubSub broadcast answer to feed (`gameplay:#{id}:answer_submitted`)

**Tests:**

- Answer submission (correct, incorrect)
- Case-insensitivity ("PARIS" = "paris")
- Trimming (" paris " = "paris")
- Cooldown enforcement (2 submissions <1s apart → error)
- Duplicate submission prevention (already solved → error)
- Placement calculation (3 users, timestamps differ by ms)
- Points awarded (10/7/3/0 based on placement)
- User stats update (total_points, podium_count if top 3, wins_count if 1st)
- Ban check (banned user → redirect)
- Game state check (not :live → error)

**Verify:**

- Start riddle, open as 3+ users
- Submit wrong answers, verify "incorrect" message
- Submit correct answer, verify "correct" + points awarded
- Check cooldown (rapid submissions blocked)
- Verify placement (1st user gets 10, 2nd gets 7, 3rd gets 3)
- Check user profiles (total_points updated)
- Ban user mid-game, verify next submission redirects

**Implementation notes:**

```elixir
# ETS setup in application.ex
:ets.new(:riddle_answers, [:bag, :public, :named_table, read_concurrency: true, write_concurrency: true])
:ets.new(:answer_cooldowns, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])

# handle_event with security checks
def handle_event("submit_answer", %{"answer" => text}, socket) do
  user = socket.assigns.current_user
  game = socket.assigns.game

  with :ok <- check_not_banned(user.id),
       :ok <- check_game_live(game),
       :ok <- check_not_already_solved(game.id, user.id),
       :ok <- check_cooldown(game.id, user.id),
       :ok <- validate_answer_input(text) do
    # Use assign_async for validation (may call content moderation API)
    {:noreply, assign_async(socket, :validation_result, fn ->
      result = Gameplay.validate_answer(game, text)
      {:ok, %{validation_result: result}}
    end)}
  else
    {:error, :banned} ->
      {:noreply, socket |> put_flash(:error, "Account suspended") |> redirect(to: ~p"/")}
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, format_error(reason))}
  end
end

# Cooldown check (ETS atomic)
defp check_cooldown(game_id, user_id) do
  now = System.monotonic_time(:microsecond)
  key = {game_id, user_id}
  case :ets.lookup(:answer_cooldowns, key) do
    [{^key, last_time}] ->
      if now - last_time < 1_000_000 do  # 1 second in microseconds
        {:error, :cooldown}
      else
        :ets.insert(:answer_cooldowns, {key, now})
        :ok
      end
    [] ->
      :ets.insert(:answer_cooldowns, {key, now})
      :ok
  end
end
```

---

## Phase 10: Live Game - Answer Feed

**Goal:** Real-time answer display with streams

**Deliverables:**

- Answer feed component (chronological, newest at top)
- **Streams pattern:** `stream(:answers, at: 0, limit: 100)`
  - Prevents memory explosion (100 viewers × 500 answers = O(1) memory with streams vs O(n) with assigns)
  - Newest answers inserted at position 0
  - Limit prevents unbounded growth
- Display: player username, answer text, time offset (ms since game start)
- PubSub subscription (`gameplay:#{id}:answer_submitted`)
- **Content moderation:** Async with optimistic display
  - Display immediately (real-time requirement)
  - Kick off Task.Supervisor job for moderation check
  - If flagged, broadcast `:answer_flagged` event, hide via stream delete
  - Two-layer moderation: local blocklist (instant) + external API (Google Perspective, async)
  - Fail-open on API errors (log, don't block gameplay)
- Highlight correct answers post-game (when play_status → :completed)
- Optional: Scroll to bottom on new answer (JS hook)

**Tests:**

- Answer broadcast (submit answer, verify appears in other users' feeds)
- Feed ordering (chronological, newest first)
- Time offset calculation (ms precision from game start)
- Content moderation flag (submit blocked word, verify hidden after async check)
- Correct answer highlight (post-game, correct answers styled differently)
- Stream limit (submit 150 answers, verify only 100 visible)

**Verify:**

- Play game with multiple users
- Submit answers, verify real-time display in all tabs
- Verify time offsets accurate (ms since game went :live)
- Submit content with blocked word, verify hidden after ~1s
- Complete game, verify correct answers highlighted

**Implementation notes:**

```elixir
# Streams setup
def mount(%{"id" => id}, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{id}:answer_submitted")
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{id}:answer_flagged")
  end

  # Load initial answers from ETS
  answers = Gameplay.get_answers(id) |> Enum.take(100)

  {:ok, socket
    |> assign(:game_start_time, game.live_date)
    |> stream(:answers, answers, at: 0, limit: 100)}
end

# Handle new answer
def handle_info({:answer_submitted, answer}, socket) do
  # Insert at position 0 (newest first)
  {:noreply, stream_insert(socket, :answers, answer, at: 0)}
end

# Async moderation
def submit_answer(game_id, user, text) do
  answer = %{id: UUID.generate(), user_id: user.id, text: text, timestamp: System.monotonic_time(:microsecond)}

  # Broadcast immediately (optimistic)
  Phoenix.PubSub.broadcast(Riddlr.PubSub, "gameplay:#{game_id}:answer_submitted", {:answer_submitted, answer})

  # Async moderation
  Task.Supervisor.start_child(Riddlr.TaskSupervisor, fn ->
    case Moderation.check(text) do
      {:flagged, reason} ->
        Phoenix.PubSub.broadcast(Riddlr.PubSub, "gameplay:#{game_id}:answer_flagged",
          {:answer_flagged, answer.id, reason})
      :ok -> :noop
    end
  end)
end

# Moderation fail-open pattern
def check(text) do
  with {:ok, text} <- local_blocklist_check(text),
       {:ok, _} <- external_api_check(text) do
    :ok
  else
    {:flagged, reason} -> {:flagged, reason}
    {:error, _api_error} -> :ok  # Fail open - don't block on API failure
  end
end
```

---

## Phase 11: Game Completion & Results

**Goal:** Post-game experience with auto-archive

**Deliverables:**

- **Auto-complete triggers:**
  - When `solve_time` expires (Oban scheduled job at `live_date + solve_time`)
  - When first correct answer submitted (immediate, cancel scheduled job)
- Post-game screen (same LiveView, different state)
  - Winner announcement (1st place user)
  - Correct answers list
  - Top 10 leaderboard (for this game)
  - Link to full leaderboard
- Update riddle stats:
  - `first_solver_id` (user_id of 1st place)
  - `first_solve_time` (seconds from start to first correct)
  - `completion_rate` (% of players who solved)
  - `average_solve_time` (avg seconds for correct solvers)
- **Auto-archive:** Oban job scheduled +3 min after completion
  - `ArchiveRiddleTransitionWorker` enqueued in `complete_riddle/1`
  - Idempotent (check play_status == :completed before archiving)
- Block submissions when :archived (LiveView mount redirect)
- Cleanup ETS entries on archive (`:ets.match_delete(:riddle_answers, {{riddle_id, :_}, :_})`)

**Tests:**

- Completion trigger (solve_time elapsed, no correct answers)
- Completion trigger (first correct answer, immediate)
- Winner announcement (1st place user displayed)
- Stats calculation (first_solver_id, first_solve_time, completion_rate, average_solve_time)
- Auto-archive job (enqueued with +3 min delay)
- Auto-archive execution (drain queue, verify :archived)
- Post-game access (view-only, no submission form)
- Archived game redirect (mount → view-only results)
- ETS cleanup (verify entries deleted after archive)

**Verify:**

- Start game, wait for solve_time to expire without answers → auto-complete
- Start game, submit correct answer → immediate complete, verify scheduled job cancelled
- View post-game screen, verify winner, correct answers, top 3
- Wait 3 min after completion, verify auto-archive
- Attempt to submit answer after archive → blocked
- Check ETS (should be empty for archived game)

**Implementation notes:**

```elixir
# Schedule auto-complete on game start
def start_riddle(riddle_id) do
  riddle = Repo.get!(Riddle, riddle_id)
  complete_at = DateTime.add(riddle.live_date, riddle.solve_time, :second)

  Multi.new()
  |> Multi.update(:riddle, Riddle.changeset(riddle, %{play_status: :live}))
  |> Multi.insert(:complete_job, fn _ ->
    %{riddle_id: riddle.id}
    |> CompleteRiddleWorker.new(scheduled_at: complete_at)
  end)
  |> Repo.transaction()
end

# Immediate complete on first correct answer
def process_correct_answer(riddle, user, timestamp) do
  # Cancel scheduled auto-complete job
  Oban.cancel_all_jobs(CompleteRiddleWorker, %{riddle_id: riddle.id})

  # Complete immediately
  complete_riddle(riddle.id, first_solver: user.id, first_solve_time: calculate_solve_time(riddle, timestamp))
end

# complete_riddle enqueues archive job
def complete_riddle(riddle_id, opts \\ []) do
  Multi.new()
  |> Multi.update(:riddle, fn _ ->
    riddle = Repo.get!(Riddle, riddle_id)
    stats = calculate_stats(riddle_id)
    Riddle.changeset(riddle, Map.merge(%{play_status: :completed}, stats))
  end)
  |> Multi.insert(:archive_job, fn _ ->
    %{riddle_id: riddle_id}
    |> ArchiveRiddleTransitionWorker.new(schedule_in: 180)  # 3 minutes
  end)
  |> Repo.transaction()
end

# Archive cleanup
def archive_riddle(riddle_id) do
  riddle = Repo.get!(Riddle, riddle_id)
  if riddle.play_status == :completed do
    :ets.match_delete(:riddle_answers, {{riddle_id, :_}, :_})
    :ets.match_delete(:answer_cooldowns, {{riddle_id, :_}, :_})
    Riddle.changeset(riddle, %{play_status: :archived}) |> Repo.update()
  else
    {:cancel, "Already archived or wrong state"}
  end
end
```

---

## Phase 12: Leaderboards

**Goal:** All-time, monthly, weekly leaderboards

**Context:** Leaderboards live in **Accounts context** (queries User schema)

**Deliverables:**

- Leaderboard LiveView (`/leaderboards`)
- Tabs: All-time, Monthly, Weekly
- **Queries:**
  - All-time: `ORDER BY total_points DESC LIMIT 100`
  - Monthly: `WHERE inserted_at >= start_of_month ORDER BY total_points DESC` (calculate on-the-fly, no separate monthly_points field)
  - Weekly: `WHERE inserted_at >= start_of_week ORDER BY total_points DESC` (calculate on-the-fly)
- Display: rank (#1, #2, ...), username/display_name, total_points, wins_count, podium_count
- Real-time updates (PubSub subscription to `accounts:leaderboard:updated`)
- Pagination (100 per page)

**Note:** No separate monthly_points/weekly_points fields. Calculate based on user.inserted_at for MVP. For more accuracy, Phase 17+ could add Submission schema with timestamps.

**Tests:**

- All-time query (top 100 by total_points)
- Monthly query (users who joined this month, sorted by points)
- Weekly query (users who joined this week, sorted by points)
- Rendering (rank, username, stats)
- Real-time update (complete game, verify leaderboard updates)
- Pagination (101 users, verify pagination)

**Verify:**

- Play games with different users, accumulate points
- Navigate `/leaderboards`
- Verify all-time shows correct ranking
- Complete game, verify real-time update
- Test monthly/weekly filters

**Implementation notes:**

```elixir
# Leaderboard query (Accounts context)
def leaderboard(:all_time, limit \\ 100) do
  from(u in User, order_by: [desc: u.total_points], limit: ^limit)
  |> Repo.all()
end

def leaderboard(:monthly, limit \\ 100) do
  start_of_month = Timex.beginning_of_month(DateTime.utc_now())
  from(u in User,
    where: u.inserted_at >= ^start_of_month,
    order_by: [desc: u.total_points],
    limit: ^limit)
  |> Repo.all()
end

# Broadcast on stats update
def increment_stats(user_id, field, amount) do
  # ... update user ...
  Phoenix.PubSub.broadcast(Riddlr.PubSub, "accounts:leaderboard:updated", :stats_changed)
end
```

---

## Phase 13: Email Notifications

**Goal:** Email for game events via Notifications context

**Context:** New **Notifications context** subscribes to Games PubSub events

**Deliverables:**

- Swoosh config (adapter: local for dev, SMTP/SendGrid for prod)
- Notifications context module
- Email templates (HEEx): game_scheduled, starting_soon (5 min warning), game_results
- **PubSub subscription pattern:**
  - Subscribe to `games:riddle:scheduled` in Application supervisor
  - Subscribe to `games:riddle:ready` (5 min warning)
  - Subscribe to `games:riddle:completed` (results)
- Send email on `:scheduled` transition (if user.notification_settings.email == true)
- Send email on `:ready` transition ("Game starting in 5 minutes!")
- Send email on `:completed` transition (results, winner, top 3)
- Respect `user.notification_settings.email` (check before sending)
- Async delivery (Oban queue `:mailers`)

**Tests:**

- Email delivery (Swoosh.TestAssertions in test env)
- Settings respect (disabled email → no send)
- Game scheduled email (riddle name, live_date, category)
- Starting soon email (5 min warning)
- Results email (winner, correct answers, player's placement)
- Unsubscribed user no email (notification_settings.email = false)

**Verify:**

- Schedule game, check email sent (Swoosh local inbox)
- Complete game, check results email
- Disable email notifications, schedule game, verify no email
- Test in production with real SMTP

**Implementation notes:**

```elixir
# Notifications context subscribes to game events
defmodule Riddlr.Notifications.Subscriber do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:scheduled")
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:ready")
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
    {:ok, state}
  end

  def handle_info({:riddle_scheduled, riddle}, state) do
    Notifications.send_game_scheduled_emails(riddle)
    {:noreply, state}
  end
end

# Send email (async via Oban)
def send_game_scheduled_emails(riddle) do
  users = Accounts.list_users_with_email_notifications()

  Enum.each(users, fn user ->
    %{user_id: user.id, riddle_id: riddle.id, template: :game_scheduled}
    |> SendEmailWorker.new(queue: :mailers)
    |> Oban.insert()
  end)
end
```

---

## Phase 14: SMS Notifications

**Goal:** SMS via Twilio integration

**Deliverables:**

- ExTwilio dependency (`{:ex_twilio, "~> 0.9"}`)
- Twilio config in runtime.exs (account_sid, auth_token, from_number from env vars)
- SMS templates: game_scheduled, starting_soon
- Send SMS on `:scheduled` transition (if communication_preference == :sms AND mobile_number present)
- Send SMS on `:ready` transition ("Game starting in 5 min!")
- Respect `user.communication_preference` and `user.notification_settings.sms`
- Async delivery (Oban queue `:mailers`, separate worker `SendSMSWorker`)

**Tests:**

- SMS delivery (mock ExTwilio.Message.create in tests)
- Settings respect (sms disabled → no send)
- Communication preference (:email → no sms, :sms → send sms)
- Game scheduled SMS
- Starting soon SMS
- Missing mobile_number → skip (no error)

**Verify:**

- Add mobile_number to profile, set preference to :sms
- Schedule game, check Twilio logs/dashboard
- Verify SMS received on real phone (staging/prod)
- Test communication_preference (email only → no SMS)

**Implementation notes:**

```elixir
# SMS worker
defmodule Riddlr.Workers.SendSMSWorker do
  use Oban.Worker, queue: :mailers, max_attempts: 3

  def perform(%{args: %{"user_id" => user_id, "message" => message}}) do
    user = Accounts.get_user!(user_id)

    if should_send_sms?(user) do
      ExTwilio.Message.create(
        to: user.mobile_number,
        from: twilio_from_number(),
        body: message
      )
    else
      {:cancel, "User preferences do not allow SMS"}
    end
  end

  defp should_send_sms?(user) do
    user.mobile_number != nil &&
    user.communication_preference == :sms &&
    user.notification_settings.sms == true
  end
end
```

---

## Phase 15: Admin Moderation

**Goal:** Content moderation, player management with 3-layer ban enforcement

**Deliverables:**

- **Moderation dashboard** (`/admin/moderation`)
  - List flagged answers (from async moderation, Phase 10)
  - List banned users
  - Search/filter by user, game, date
- **Flag answer** (moderator action)
  - Hide answer from feed (broadcast `:answer_hidden` to PubSub)
  - Mark in database (if persisting flags, or just ETS for MVP)
- **Ban player** (moderator/admin action)
  - Update `account_status` to `:banned`
  - **Three-layer enforcement:**
    1. Mount check (immediate redirect on next page load)
    2. PubSub broadcast `user:#{user_id}:account_banned` → active sessions disconnect
    3. Periodic re-check every 5 min in LiveView (`Process.send_after` → re-fetch user)
  - Block all gameplay access (mount guard in GameLive)
- **Unban player** (super_admin only)
  - Update `account_status` to `:active`
  - Broadcast `user:#{user_id}:account_unbanned`
- **Permission checks:**
  - Moderator: can flag/hide answers, ban players
  - Editor: cannot ban (only manage riddles)
  - Super_admin: all permissions

**Tests:**

- Flag answer (moderator role, answer hidden from feed)
- Hide flagged answer (broadcast to PubSub, removed from streams)
- Ban player (account_status updated)
- Banned access restriction (mount → redirect)
- PubSub ban broadcast (active session disconnects)
- Periodic ban check (banned mid-session, disconnects after 5 min max)
- Unban player (super_admin only)
- Moderator role permission (can ban but not create riddles)
- Editor role permission (can create riddles but not ban)

**Verify:**

- Login as moderator, flag answer, verify hidden in all active feeds
- Ban player, verify:
  - Player's active game session disconnects immediately (PubSub)
  - Player cannot mount game on refresh (mount check)
  - Periodic check works (wait 5 min, banned user auto-disconnects)
- Unban player, verify can access game again

**Implementation notes:**

```elixir
# Ban player (Games or Accounts context)
def ban_player(user_id, reason) do
  user = Repo.get!(User, user_id)

  Multi.new()
  |> Multi.update(:user, User.changeset(user, %{account_status: :banned}))
  |> Multi.run(:broadcast, fn _, _ ->
    Phoenix.PubSub.broadcast(Riddlr.PubSub, "user:#{user_id}", :account_banned)
    {:ok, :broadcasted}
  end)
  |> Repo.transaction()
end

# LiveView mount check
def mount(_params, session, socket) do
  user = get_user_from_session(session)

  if user.account_status == :banned do
    {:ok, socket |> put_flash(:error, "Account suspended") |> redirect(to: ~p"/")}
  else
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
      schedule_ban_check()
    end
    {:ok, assign(socket, :current_user, user)}
  end
end

# Periodic ban check
def handle_info(:check_ban_status, socket) do
  user = Accounts.get_user!(socket.assigns.current_user.id)
  if user.account_status == :banned do
    {:noreply, socket |> put_flash(:error, "Account suspended") |> redirect(to: ~p"/")}
  else
    schedule_ban_check()
    {:noreply, socket}
  end
end

defp schedule_ban_check, do: Process.send_after(self(), :check_ban_status, :timer.minutes(5))

# PubSub ban notification
def handle_info(:account_banned, socket) do
  {:noreply, socket |> put_flash(:error, "Account suspended") |> redirect(to: ~p"/")}
end
```

---

## Phase 16: Production Polish

**Goal:** Deployment ready

**Deliverables:**

- **Env config:**
  - prod.exs (compile-time config)
  - runtime.exs (runtime env vars: DATABASE*URL, SECRET_KEY_BASE, TWILIO*\_, SMTP\_\_, SENTRY_DSN)
- **DB connection pooling:**
  - Pool size: 15+ (5 game_lifecycle + 3 mailers + 5 default + buffer)
  - Timeout: 15000ms
- **Database indices:**
  - users: username (unique), total_points, account_status, role
  - riddles: play_status, live_date, category
  - tags: name (unique, lowercase)
  - riddle_tags: riddle_id + tag_id (composite unique)
- **Error tracking:** Sentry integration
  - LoggerBackend for automatic error capture
  - Custom breadcrumbs for game events
- **Monitoring:** AppSignal or similar
  - Custom instrumentation for answer submission latency
  - Oban job metrics
- **Deployment guide:** Fly.io or Render
  - fly.toml / render.yaml config
  - Release config (mix release)
  - Database migrations in release command
- **Accessibility audit:**
  - Keyboard navigation (tab through forms, enter to submit)
  - Screen reader labels (aria-label for icons, form inputs)
  - Focus indicators (visible :focus styles)
  - Color contrast (WCAG AA minimum)
- **Mobile responsive:**
  - Tailwind breakpoints (sm, md, lg)
  - Touch-friendly buttons (min 44px tap target)
  - Viewport meta tag
  - Test on iOS Safari, Android Chrome

**Tests:**

- Load test (100 concurrent users, 10 active games, k6 or Artillery)
- Query performance (EXPLAIN ANALYZE for leaderboard, riddle list)
- Error handling (network failures, DB timeouts, external API failures)
- Release build (`MIX_ENV=prod mix release`, verify starts)

**Verify:**

- Deploy to prod (Fly.io: `fly deploy`)
- Load test (verify <200ms p95 for answer submission)
- Mobile testing (BrowserStack or real devices)
- Accessibility audit (axe DevTools, WAVE)
- Error tracking (trigger error, verify Sentry captures)
- Monitoring (verify AppSignal dashboards populate)

**Implementation notes:**

```elixir
# runtime.exs
config :riddlr, Riddlr.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")

config :ex_twilio,
  account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
  auth_token: System.get_env("TWILIO_AUTH_TOKEN")

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: System.get_env("SENTRY_ENV") || "production"

# Migration for indices
defmodule Riddlr.Repo.Migrations.AddIndices do
  use Ecto.Migration

  def change do
    create index(:users, [:total_points])
    create index(:users, [:account_status])
    create index(:riddles, [:play_status])
    create index(:riddles, [:live_date])
  end
end
```

---

## Key Dependencies

- Auth (Phase 2) before admin (Phase 5)
- Riddle schema (Phase 4) before lifecycle (Phase 7)
- Lifecycle (Phase 7) before gameplay (Phases 8-11)
- Leaderboards (Phase 12) depend on completion (Phase 11)
- Notifications (13-14) can parallelize after Phase 7

## Reusable Patterns

- State machine transitions (Phase 7) reused in notifications (13-14)
- PubSub pattern (Phase 8) reused in gameplay (9-10), leaderboards (12), moderation (15)
- Admin auth `on_mount` (Phase 5) pattern for moderation (Phase 15)
- Oban idempotency (Phase 7) pattern for all workers (11, 13, 14)
- ETS concurrent writes (Phase 9) pattern for cooldowns, answer storage

---

## Resolved Questions

1. **Content moderation:** ✅ Async two-layer (local blocklist + external API), fail-open on API errors
2. **Monthly/weekly leaderboards:** ✅ Calculate on-the-fly based on user.inserted_at (no separate fields for MVP)
3. **Answer feed storage:** ✅ ETS (ephemeral, :bag table with composite keys)
4. **Admin auth:** ✅ `on_mount` hooks (LiveView-first, not controller plugs)
5. **Answer storage:** ✅ ETS over GenServer (concurrent writes, no coordination needed)
6. **Countdown:** ✅ Hybrid (server tick 1s, JS hook updates 100ms)
7. **Player count:** ✅ Phoenix Presence (assigns, not streams)
8. **Answer feed rendering:** ✅ Streams with limit 100 (memory efficiency)
9. **Auto-transitions:** ✅ Oban workers (survive server restart, not LiveView process)
10. **Ban enforcement:** ✅ Three-layer (mount + PubSub + periodic check)

## Unresolved Questions

1. **Lobby "Ready" button:** Required for MVP or defer? Spec mentions but unclear if affects gameplay. → Defer to Phase 17 backlog.

2. **Private games:** Phase 2 or defer? Adds authorization complexity (game ownership, invite codes). → Defer to Phase 17 backlog.

3. **Hint system:** Auto-show after hint_delay during live game? Needs timer logic similar to countdown. → Defer to Phase 17 backlog.

4. **Timezone handling:** Display live_date in user's local TZ or UTC? Affects countdown accuracy for global players. Current plan uses UTC. → User testing needed.

5. **Scale:** Expected concurrent players per game? Affects PubSub (single channel vs sharding). Current plan assumes <1000 per game (no sharding). → Monitor in production.

6. **Account verification:** SMS/email verification before first play—Phase 2 or 3? → Defer to Phase 17 (security enhancement).

7. **Streak calculation:** "Consecutive days playing" reset at midnight UTC or 24-hr window? Spec mentions streak bonuses (Phase 2 backlog) but not in MVP. → Defer to Phase 17.

8. **Answer feed scroll behavior:** Auto-scroll to bottom on new answer? Stick to current position? → User testing needed.

9. **Content moderation API choice:** Google Perspective vs alternatives (OpenAI moderation, AWS Comprehend)? → Evaluate in Phase 10 implementation.

10. **Leaderboard caching:** Should we cache top 100 in ETS/Redis for performance? → Implement if query becomes bottleneck (monitor in prod).

---

## Research Notes

Detailed research findings from specialist agents:

- `research/oban-patterns.md` - Worker structure, idempotency, scheduling patterns
- `research/liveview-patterns.md` - Countdown, Presence, streams, assign_async, cooldowns
- `research/otp-answer-storage.md` - ETS vs GenServer decision, table structure
- `research/security-patterns.md` - Admin auth, role permissions, content moderation, ban enforcement
- `research/context-boundaries.md` - 5-context architecture, PubSub namespacing

(These files can be deleted after implementation)
