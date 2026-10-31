# Riddlr — Domain

How Riddlr works, in domain terms. Terms in **bold** are defined in
[`GLOSSARY.md`](../GLOSSARY.md); this doc does not redefine them.

It names no modules, functions, files, tables or message topics. Those change;
the rules here should not. If code and this doc disagree, one of them is wrong —
find out which.

## The shape of a game

One **Riddle** is one game. There are no rounds or turns. Every **Player** who
joins races at the same time, from the **Live date** until the **Solve time**
runs out. The first correct **Guess** does not end the game: the riddle stays
live for its full Solve time so every player can still solve it and earn
**Points**.

## People and rights

Every account is a **Player**. Some players also hold a role:

| Role | Manage riddles, categories and practice riddles | Manage users | Moderate guesses | Ban players | See stats | Admin pages |
|---|---|---|---|---|---|---|
| **Super admin** | yes | yes | yes | yes | yes | yes |
| **Moderator** | no | no | yes | yes | yes | yes |
| **Editor** | yes | no | no | no | no | yes |
| **Viewer** | no | no | no | no | yes | no |
| Player | no | no | no | no | no | no |

Roles do not stack: a moderator cannot edit riddles, and an editor cannot
moderate. **Admin** means super admin, moderator or editor.

## Riddle lifecycle

A riddle has a **Play status** and a **Publish status**. They are separate:
publish status says whether the riddle may run; play status says where it is.

```
closed ──schedule──▶ scheduled ──▶ ready ──▶ live ──▶ completed ──▶ archived
   ▲                     │           │
   └────── unschedule ───┴───────────┘
```

| From → to | Trigger | When |
|---|---|---|
| closed → scheduled | Admin **Schedule**s | On save |
| scheduled → ready | Automatic | **Live date** minus the **Ready window** (default 10 min) |
| ready → live | Automatic | At the Live date |
| live → completed | Automatic | When the **Solve time** runs out (default 2 min) |
| completed → archived | Automatic | When **Post-game** ends (default 3 min; 0 archives at once) |
| scheduled or ready → closed | Admin **Unschedule**s | On save |

Rules every transition obeys:

- Only the moves in the diagram are allowed. Anything else is refused.
- Only a published riddle moves. An automatic step that finds the riddle
  unpublished, missing, or in the wrong status gives up for good; it does not
  retry. Only a failed write retries.
- Each step, once saved, sets up the next one: going live sets up completion,
  completing sets up archive.
- Everyone watching hears about a step only after it is saved. A step that
  fails is never announced.

### Schedule, reschedule, unschedule

All admin edits go through one save. On each save the system compares the
stored riddle with the edit and decides which of four things happened:

1. **Unschedule** — a scheduled or ready riddle is set back to draft. Its
   pending steps are dropped and it returns to closed. Its Live date stays but
   means nothing until it is scheduled again. This is the only way to
   unschedule.
2. **Schedule** — a closed riddle is published with a Live date in the
   future. It becomes scheduled and its ready and live steps are set up.
3. **Reschedule** — a scheduled or ready riddle's Live date or Ready window
   changes. Its pending steps are replaced to match. A past Live date is
   allowed here: the riddle goes ready and live at once.
4. **Plain edit** — anything else. The riddle is saved and nothing is
   scheduled.

A riddle that cannot be scheduled — a draft, no Live date, a past Live date
on a closed riddle, a riddle already past ready — is not an error. The save
succeeds; it just schedules nothing. The riddle and its steps are saved
together or not at all.

Deleting a riddle drops its pending steps, its guesses and its solves.

## Play flow

### Home

Home shows the **Next riddle**. Before it goes live, Home counts down to the
Live date. A ready riddle also shows how many players wait in the Lobby, and
only a ready riddle offers a way into it. A scheduled riddle tells players to
come back at the Live date. Once live, Home shows the time left and how many
have solved it. With no Next riddle, Home says nothing is scheduled and
offers a random **Practice riddle**. A player can peek at its answer or ask
for another one. A practice riddle takes no guesses and scores nothing. With
no practice riddles, Home leaves the note out.

Below that, a timeline walks through a round, ending at the Next riddle's
Solve time. Home then lists riddles coming up (without their text) and, as
"Previously", the last finished riddle with its Answer and First solver.

### Lobby

The **Lobby** opens when a riddle turns ready and closes when it goes live. A
scheduled riddle has no Lobby yet. Players in the Lobby see who else is there
and a shared countdown to the Live date. When the riddle goes live, every
player in the Lobby moves to Play at the same moment.

### Game clock

Each riddle has one **Game clock**, shared by every viewer. It ticks once a
second on the second, so all players see the same number at the same moment.
It counts to the Live date, then down the Solve time, then stops. If the
riddle is rescheduled, every open countdown moves with it.

### Play

While the riddle is live, players submit **Guesses**. Each guess passes these
checks in order:

1. The player is not banned.
2. The riddle is live.
3. The player has not already solved it.
4. The guess is not blank and is at most 500 characters.
5. The player's **Cooldown** has passed (1 s since their last guess).

The Cooldown check runs last so that a blank or too-long guess does not cost
the player their next second.

A guess is correct if it matches any of the riddle's **Answers**, ignoring
case and outer spaces. A player who solves the riddle can guess no more. A
player who guesses wrong may keep guessing.

Every guess goes on the **Feed** for all players. The text of a correct guess
is hidden — the feed shows "solved it — 2nd" instead — because the riddle
stays live and the text would give the Answer away. Wrong guesses get a
taunt.

### Moderation

Text goes through two checks:

- A word blocklist, run before the guess is stored or shown. Banned words are
  masked, so nothing unclean ever reaches the Feed.
- An outside check, run after the guess is shown so it never slows the race.
  If it **Flag**s a guess, that guess is removed from every Feed. If the check
  fails, the guess stands. This check is a stub today and passes everything.

A **Ban** takes effect at once: a banned player on Play or Results can no
longer guess or chat.

### Results and Post-game

When the riddle completes, every player moves to Results. Results shows the
**First solver**, the **Podium** and the **Leaderboard**, and the full Feed with
correct guesses now shown. During **Post-game** players can **Chat**, and a
countdown shows how long until **Archive**. At Archive chat closes and the
Leaderboard stays. A page already open keeps its Feed; a page opened after
Archive shows an empty Feed. Results also points to the Next riddle.

A player who opens Play for a completed riddle goes to Results; for an
archived riddle, to Home.

## Scoring

**Placement** is a solver's order among correct guesses, by the moment each
guess arrived. Points by placement:

| Placement | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11+ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Points | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |

Points are awarded the moment a player solves, not at completion. Each player
keeps running totals of points, **Wins** (placement 1) and podiums (placement
1–3).

The first player to solve is recorded on the riddle as **First solver**, with
their time from the Live date. If two players solve at once, only one is
recorded.

At completion the riddle records its **Completion rate** and saves one
**Solve** per solver. The status change and the solves are saved together.

## What lasts and what does not

| Kept for good | Gone at Archive (or on server restart) |
|---|---|
| Riddle, its Play and Publish status, First solver, Completion rate | Guesses and the Feed |
| Solves (placement, points, time) | Cooldowns |
| Player totals: points, wins, podiums | — |

Chat is never kept: it reaches whoever is on Results at the time and nothing
more.

## Known gaps

- **Unpublishing a live or completed riddle strands it.** Only scheduled and
  ready riddles unschedule. A live or completed riddle set to draft is saved,
  then every later step refuses it, so it never completes or archives. (#40)
- **Points and placement can drift.** Placement comes from the live guesses;
  points are saved at once. A crash between the two loses the points for good.
  The player cannot retry, because they count as having solved.
- **A server restart wipes live guesses.** Placement, the Feed and Cooldowns
  are lost; points already awarded stay.
- **The Cooldown is not exact.** Two guesses sent at the same moment can both
  pass. It is a convenience, not a security control.
- **Hints are not shown.** Riddles carry a Hint and a delay, but players never
  see them.
- **No way to ban from the app.** Ban works, but no admin page sets it.
  "Suspended" exists as an account status but blocks nothing. (#41)
- **Chat skips the outside moderation check.** Only the blocklist runs on it. (#42)
- **Chat is lost on reload.** A player who reloads Results sees no earlier
  chat. (#42)
- **Player counts are Lobby only.** Play shows how many have solved, not how
  many are present.
- **Profile shows only username and email**, not the player's totals.
