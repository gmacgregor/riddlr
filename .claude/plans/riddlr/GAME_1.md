# Riddlr Game Specification

## Overview

Riddlr is an Elixir/Phoenix real-time multiplayer riddle game. Admins create riddles (wordplay with one or many acceptable answers). Players compete in real time to solve them. Key pillars: anticipation, addiction to winning, real-time experience, leaderboards.

## Authentication

- phx.gen.auth for MVP (local accounts, passwords, sessions)
- Future: external auth via TLD cookie, thin player record keyed by external ID
- Players must verify account via SMS or email before playing
- Admins can ban players

## Game Mechanics

**Scoring:**
- 1st place: 10 points
- 2nd place: 7 points
- 3rd place: 3 points
- All others: 0 points

**Tie-breaking:** Shared placement. If two players submit correct answer at same millisecond, both get same rank/points.

**Answer validation:** Case-insensitive, whitespace-trimmed, exact match against the answers list. No fuzzy/partial matching.

**Submission cooldown:** 1-second cooldown between submissions per player.

**Unlimited attempts** within solve_time. After correct answer, no further submissions allowed.

**Content moderation:** Answers checked for racist/inflammatory content; flagged answers hidden from view.

## Play Status Flow

```
:closed -> :scheduled -> :ready -> :live -> :completed -> :archived
```

- `:closed` — default, not yet configured
- `:scheduled` — live_date is set, players can be notified
- `:ready` — countdown period, lobby is active
- `:live` — game in progress, accepting answers
- `:completed` — game ended, results visible, post-game screen
- `:archived` — historical record, answer feed closed

**State Machine:**

```
  +--------+     set live_date     +-----------+     countdown     +-------+
  | closed | ------------------->  | scheduled | ----------------> | ready |
  +--------+                       +-----------+                   +-------+
                                                                      |
                                                                  go live
                                                                      |
                                                                      v
  +----------+    3 min after   +-----------+     solve_time ends   +------+
  | archived | <-- first solve | completed | <-------------------- | live |
  +----------+                 +-----------+                       +------+
```

## Game Lobby (Pre-Live)

When game is in `:ready` state:
- Countdown timer to live
- List of registered/waiting players
- Riddle category and difficulty shown
- "Ready" button per player

## Real-Time Game UI

- Block of text displaying the riddle
- Simple text input for answer submission
- All player answers shown in real time (LiveView), ordered chronologically
- Each answer shows: player name, answer text, time offset from game start (millisecond precision)
- Player count shown in real time

## Post-Game

- Winner announced
- Correct answer(s) revealed
- The correct solution is **highlighted in the answer feed** regardless of which player submitted it
- Leaderboard shown

## Auto-Archive

Games automatically transition from `:completed` to `:archived` **3 minutes** after being solved (first correct answer). Once archived, the answer feed is closed — no further player interaction/chat.

## Schemas

### Riddle

```elixir
field :name, :string                          # riddle name
field :description, :string                   # riddle text
field :publish_status, Ecto.Enum,             # :draft | :published | :archived, default: :draft
field :live_date, :utc_datetime               # when game becomes available
field :play_status, Ecto.Enum,                # :closed | :scheduled | :ready | :live | :completed | :archived, default: :closed
field :solve_time, :integer, default: 120     # seconds allowed to solve
field :answers, {:array, :string}, default: []  # acceptable answers
field :category, Ecto.Enum                    # :wordplay | :trivia | :logic | :lateral_thinking
field :difficulty, Ecto.Enum, default: :medium  # :easy | :medium | :hard | :expert
field :hint, :string                          # optional hint text
field :hint_delay, :integer, default: 60      # seconds before hint is shown
field :max_attempts_per_player, :integer      # optional, nil = unlimited
field :completion_rate, :float                # calculated: % of players who solved
field :average_solve_time, :integer           # calculated: avg solve time in ms
field :active_player_count, :integer, default: 0  # real-time player count
field :first_solve_time, :utc_datetime        # when first correct answer was submitted

belongs_to :created_by, User                  # audit: who created
belongs_to :edited_by, User                   # audit: last editor
belongs_to :first_solver, Player              # first correct answer
has_many :tags, through: [:riddle_tags, :tag] # tags via join table
```

### Tag

```elixir
field :name, :string  # unique, lowercase
has_many :riddles, through: [:riddle_tags, :riddle]
```

- Separate table, many-to-many with riddles via RiddleTag join
- Admin UI: autocomplete from existing tags when tagging a riddle

### RiddleTag (join)

```elixir
belongs_to :riddle, Riddle
belongs_to :tag, Tag
# unique index on [:riddle_id, :tag_id]
```

### Player / User

```elixir
# phx.gen.auth fields (email, hashed_password, confirmed_at, etc.)
field :username, :string                      # required, unique
field :email_address, :string                 # optional, unique
field :mobile_number, :string                 # optional, for SMS
field :communication_preference, Ecto.Enum, default: :email  # :email | :sms
field :account_status, Ecto.Enum, default: :active  # :active | :inactive | :banned
field :display_name, :string                  # optional, shown instead of username
field :total_points, :integer, default: 0     # cached for leaderboard perf
field :wins_count, :integer, default: 0       # 1st place count
field :podium_count, :integer, default: 0     # top 3 finishes
field :games_played, :integer, default: 0
field :current_streak, :integer, default: 0   # consecutive days playing
field :longest_streak, :integer, default: 0
field :last_active_at, :utc_datetime
field :notification_settings, :map, default: %{}  # per-channel on/off toggles
```

Notification settings map shape:
```elixir
%{
  "sms" => true | false,
  "email" => true | false,
  "in_app" => true | false
}
```

### No separate Submission schema

Answers are displayed in real time via LiveView. No persistent submission records table for MVP. Can add later if analytics warrant it.

### Achievements — Phase 2

Achievement and PlayerAchievement schemas deferred. Track streaks in player schema now; badge system later.

## Admin System

**Roles:**
- `super_admin` — full access
- `moderator` — review flags, ban players, hide answers
- `editor` — create/edit riddles, schedule games
- `viewer` — read-only access

**Riddle Management (MVP):**
- CRUD for riddles
- Preview/test mode (play without affecting stats)
- Duplicate riddle detection
- Tag management with autocomplete

**Game creation:** Admin-only. No user-created games.

**Advanced game management (cancel, pause, extend, void, clone):** Phase 2.

**Analytics dashboard:** Phase 2.

## Leaderboards

Three views:
- **All-time** — total points, lifetime
- **Monthly** — resets each calendar month
- **Weekly** — resets each calendar week

## Notifications

**Channels:** SMS, Email, In-app

**Preferences:** Simple per-channel on/off toggles (stored in player.notification_settings)

**Notification types:**
- Game starting soon (when :scheduled -> :ready)
- Game results

## Private Games

Invite-only games: admin creates a game with a visibility setting. Private games accessible only via invite link/code. Public games visible to all.

## Security & Privacy

- phx.gen.auth defaults (password hashing, session management)
- Account verification (SMS or email) required before playing
- Don't display email addresses publicly

## Accessibility

- Keyboard navigation support
- Screen reader compatibility
- High contrast mode
- Focus indicators
- Colorblind-friendly color schemes

## Mobile Responsiveness

- Touch-optimized submit buttons
- Prevent zoom on input focus (iOS)
- Responsive layout for all screen sizes

## ERD

To be generated during implementation. Covers: Riddle, Tag, RiddleTag, User/Player, and their relationships.

## Phase 2 Backlog

- Achievement/badge system (Achievement, PlayerAchievement schemas)
- Player ranks/levels (Bronze through Diamond)
- Daily challenges / Riddle of the Day (2x points)
- Streak bonus points
- Admin analytics dashboard
- Advanced game management (cancel, pause, extend, void, clone)
- Category-specific leaderboards
- Full submission tracking schema
