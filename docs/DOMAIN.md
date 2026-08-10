## Domain Model

| Entity | File | Notes |
|---|---|---|
| `Riddlr.Games.Riddle` | `lib/riddlr/games/riddle.ex` | Central aggregate. `answers` (array of accepted strings), `difficulty`, `hint`/`hint_delay`, `live_date`, `play_status`, `publish_status`, timing knobs (`ready_before_seconds`, `solve_time`, `archive_after_seconds`, `live_until_solved`), stats (`first_solve_time`, `completion_rate`, `average_solve_time`) |
| `Riddlr.Games.Category` | `lib/riddlr/games/category.ex` | Taxonomy, unique `name` |
| `Riddlr.Accounts.User` | `lib/riddlr/accounts/user.ex` | `email`, `username`, `role`, `account_status`, denormalized `total_points` / `wins_count` / `podium_count` |
| `Riddlr.Accounts.UserToken` | `lib/riddlr/accounts/user_token.ex` | Session / magic-link / email-confirm tokens |
| `Riddlr.Accounts.Scope` | `lib/riddlr/accounts/scope.ex` | Phoenix 1.8 scope wrapper |

Relationships:

- `Category` has_many `Riddle` (required `category_id`)
- `Riddle` belongs_to `first_solver` → `User` (nullable)
- `User` has_many `UserToken`

**There is no answer/submission/leaderboard table.** Submissions, cooldowns and
placement live in ETS (`:riddle_answers` bag, `:answer_cooldowns` set) owned by
`Riddlr.Gameplay.EtsOwner` and are wiped on archive. Only aggregates flush back to
`riddles` and `users`.

## Bounded Contexts

- `Riddlr.Games` (`lib/riddlr/games.ex`) — riddle/category CRUD + all lifecycle
  transitions, broadcasts on `games:riddle:*`
- `Riddlr.Gameplay` (`lib/riddlr/gameplay.ex`) — the Answer race. `submit_answer/3`
  owns the guard chain, cooldown, placement, points, first solver and the
  live-until-solved decision; the ETS primitives behind it are private. Also exposes
  read-side state (`solved?/2`, `get_answers/1`, `get_top_solvers/2`,
  `get_completion_stats/1`), the chat broadcast and ETS cleanup
- `Riddlr.Accounts` — registration, magic-link/password auth, `award_game_points/3`
- `Riddlr.Authorization` — hierarchical roles `super_admin > moderator > editor >
  viewer > player`; permissions `:manage_riddles`, `:manage_users`,
  `:moderate_content`, `:ban_players`, `:view_analytics`
- `Riddlr.Moderation` — blocklist + stubbed external API, fail-open, run async under
  `Riddlr.TaskSupervisor`

## Lifecycle

```
closed → scheduled → ready → live → completed → archived
                 ↖──── (draft rollback) ────↙
```

Enforced by `@valid_transitions` in `riddle.ex` via
`validate_play_status_transition/1`. Orthogonal `publish_status`
(`draft | published`) — workers refuse to transition unpublished riddles.

Driven by Oban workers in the `game_lifecycle` queue (`lib/riddlr/workers/`), all
using string args, `unique: [period: {1, :hour}, keys: [:riddle_id]]`, and idempotent
via `{:cancel, ...}` state guards:

| Worker | Fires |
|---|---|
| `ReadyRiddleTransitionWorker` | `live_date - ready_before_seconds` (default 600s) |
| `LiveRiddleTransitionWorker` | at `live_date` |
| `CompleteRiddleWorker` | `solve_time` after live (default 120s), skipped if `live_until_solved` |
| `ArchiveRiddleTransitionWorker` | `archive_after_seconds` after completion (default 180s) |

Scheduling/cancellation goes through `Riddlr.Games.RiddleScheduler`.

## Gameplay Flow

**One riddle = one game.** No turns, no rounds — every player races simultaneously.

0. **Author/schedule** (`lib/riddlr_web/live/admin/riddle_live/form_component.ex`) —
   admin creates riddle (`closed`/`draft`), publishes with a `live_date`.
   `Games.schedule_riddle/3` runs an `Ecto.Multi`: sets `scheduled`, inserts the ready
   + live jobs, broadcasts `{:riddle_scheduled, riddle}`.
1. **Ready** — worker flips to `ready`, broadcasts on `games:riddle:ready`.
2. **Lobby** — `GET /game/:id/lobby` → `GameLive.Lobby`. On connect: `Presence.track/4`
   on `game:lobby:{id}`, subscribe to that topic + `games:riddle:live`, and
   `LobbyTimer.ensure_started/2`. `Riddlr.LobbyTimer` is a per-riddle GenServer under
   `LobbyTimerSupervisor`/`LobbyTimerRegistry` broadcasting `{:countdown_tick, seconds}`
   once per wall-clock second, then stopping at 0. Player count = `Presence.list |> map_size`.
3. **Live** — `Games.transition(id, :live)` sets `live`, broadcasts `{:riddle_live, riddle}`;
   every lobby LiveView `push_navigate`s to `/game/:id/play` simultaneously.
4. **Race** — `GameLive.Play` subscribes to completed/archived/answer_submitted/
   answer_flagged/user-ban topics. Feed rebuilt from ETS, usernames batch-loaded
   (`Accounts.get_users_by_ids/1`), streamed with `limit: 100`.
   `Gameplay.submit_answer/3` guard chain: not banned → game live → not already
   solved → non-empty and ≤500 chars → 1s per-user cooldown (checked last, since
   the check mutates). Matching is case-insensitive and
   trimmed against `riddle.answers`. Answers store a monotonic timestamp +
   `solve_time_ms` offset from `live_date` and broadcast to every player's feed.
   Moderation runs async; flagged answers are `stream_delete`d for everyone.
   Wrong answers get a random taunt + shake animation.
5. **Scoring** — placement = count of correct ETS entries with timestamp ≤ yours.
   Gameplay owns the points table (**1st=10, 2nd=9 … 10th=1, 0 after**) and passes the
   value to `Accounts.award_game_points/3`, which atomically increments `total_points`,
   plus `podium_count` for top-3 and `wins_count` for 1st.
   On placement 1: if `live_until_solved`, the winner cancels the pending
   `CompleteRiddleWorker` and completes the riddle immediately — the conditional
   `update_all ... where is_nil(first_solver_id)` in `record_first_solver/3` is the
   concurrency gate. Otherwise the timed game keeps running.
6. **Complete** — `Games.transition(id, :completed, stats)` writes `completed`, `first_solver_id`,
   `first_solve_time`, `completion_rate` (unique solvers / unique answerers), enqueues
   archive. Play LiveView highlights correct answers, loads `get_top_solvers/2`
   (fastest 10) and switches to a tabbed Leaderboard / post-game Chat panel with a
   cooldown countdown. Chat reuses the `answer_submitted` topic with `chat: true`.
7. **Archive** — `Games.transition(id, :archived)` writes `archived` and drops that riddle's
   ETS rows via `Gameplay.cleanup_riddle/1` (as does `Games.delete_riddle/1`).

Every Play status transition goes through one interface, `Games.transition/3`, which
owns the guards (published + `Riddle.valid_transitions/0`), the write, the follow-on
job and the post-commit broadcast. It returns `{:ok, riddle}`, `{:error, :not_found}`,
`{:unpublished, status}`, `{:invalid, from, to}` or `{:error, changeset}`; the workers
are pure Oban plumbing over it (`Riddlr.Workers.Transition`) and cancel — rather than
retry — on the three permanent failures.

## Surfaces (`lib/riddlr_web/router.ex`)

- Player: `/game/:id/lobby`, `/game/:id/play`, `/profile`
- Admin (`RiddlrWeb.AdminAuth.:require_admin`): `/admin/riddles`, `/admin/categories`
- Auth: register / log-in (password + magic link) / settings

Design direction: `docs/superpowers/specs/2026-03-10-lobby-play-redesign.md` and
`design/` — dark, violet-accented "tense social game show" aesthetic, mobile-first.

## Known Gaps / Gotchas

- **No discovery UI.** `/` renders a placeholder; players reach a lobby by direct URL.
- `hint` / `hint_delay` / `average_solve_time` exist in the schema but no hint-reveal
  logic exists anywhere in `lib/`.
- Presence is lobby-only; the play view has no player count.
- Restarting `Gameplay.EtsOwner` wipes all in-flight answers.
- The 1s cooldown is non-atomic — UX rate limit only, not a security control.
- `docs/riddle-lifecycle.md` is **stale**: claims `live → completed` on first correct
  answer (only true with `live_until_solved`), 5-min ready window (actually
  `ready_before_seconds`, default 600s), `default` queue (actually `game_lifecycle`),
  and `archive_after_seconds: 3` (schema default 180).
- Play LiveView's redirect on archive is commented out, so players stay on the page.
