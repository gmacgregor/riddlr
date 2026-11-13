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

| Role | Manage riddles, categories, seasons and practice riddles | Manage users | Moderate guesses | Ban players | See stats | Admin pages |
|---|---|---|---|---|---|---|
| **Super admin** | yes | yes | yes | yes | yes | yes |
| **Moderator** | no | no | yes | yes | yes | yes |
| **Editor** | yes | no | no | no | no | yes |
| **Viewer** | no | no | no | no | yes | no |
| Player | no | no | no | no | no | no |

Roles do not stack: a moderator cannot edit riddles, and an editor cannot
moderate. **Admin** means super admin, moderator or editor.

### Guests

A visitor who is not signed in can watch a game: the Lobby, Play and
Results. They see the countdown, who is in the Lobby, the guess feed, the
board and the post-game chat. They cannot take part: no guess or chat form
shows, and the system refuses a guess or chat message from them. They are not
counted in the Lobby. Each of these pages asks them to log in or sign up.

### Profile

Each player has one account page, `/profile`, and sees only their own. It
shows their username and email and holds the account forms. Changing email
needs a log-in in the last 10 minutes; other forms need only a log-in.

A player can opt in to email **Notifications** and to texts at sign-up or on
their profile. Both are off by default. On their profile they
also pick a **Notification lead time**, and the page sums up their choice,
e.g. "Email + Text (•••• 1234), 30 min before". See
[Notifications](#notifications).

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
   pending steps and Notification sends are dropped and it returns to closed. Its Live date stays but
   means nothing until it is scheduled again. This is the only way to
   unschedule.
2. **Schedule** — a closed riddle is published with a Live date in the
   future. It becomes scheduled and its ready and live steps are set up,
   along with the 30 min and 1 hour Notification sends.
3. **Reschedule** — a scheduled or ready riddle's Live date or Ready window
   changes. Its pending steps and its pending 30 min and 1 hour Notification
   sends are replaced to match. A past Live date is allowed here: the riddle
   goes ready and live at once.
4. **Plain edit** — anything else. The riddle is saved and nothing is
   scheduled.

A riddle that cannot be scheduled — a draft, no Live date, a past Live date
on a closed riddle, a riddle already past ready — is not an error. The save
succeeds; it just schedules nothing. The riddle and its steps are saved
together or not at all.

Deleting a riddle drops its pending steps, its guesses and its solves.

## Seasons

A **Season** has a name, an optional description, and a start and end date.
Dates are calendar days in the display time zone (Toronto by default), as
Live dates are, and both ends count, so a season can be one day long. A
season starts at midnight on its start date and ends at midnight after its
end date, both in that zone. The system stores those two moments in UTC.
Editors and super admins manage seasons on the admin seasons page;
moderators cannot.

A season's status comes from the clock and is never stored:

| Status | When |
|---|---|
| Upcoming | Before its start |
| Current | From its start until its end |
| Past | From its end on (a **Past season**) |

The system refuses a season when:

- another season has the same name, ignoring case;
- its end date is before its start date;
- it shares a day with another season. The error names that season.

Seasons may sit back to back or leave gaps between them. Days in a gap
belong to no season.

What an edit may change depends on status:

| Status | Name and description | Start date | End date |
|---|---|---|---|
| Upcoming | yes | yes | yes |
| Current | yes | no | yes |
| Past | yes | no | no |

The current season's end date may move before today; the season is then
past at once. A season can be deleted only while no riddle belongs to it.

### Riddles and seasons

Every riddle belongs to one season from the moment it is created, drafts
included. Practice riddles belong to none. The admin riddles list shows each
riddle's season.

The riddle form offers only the current and upcoming seasons, with no blank
choice, so an editor can file a draft under a season that has not started.
A new riddle starts in the season holding its Live date, or else the current
season, or else the soonest upcoming one. A riddle in a past season shows its
season as text and cannot pick another. With no current or upcoming season,
the form asks the editor to create a season first.

A save keeps a riddle's season in step with its Live date. It picks the
season in this order:

1. If the editor changed the season in this save, keep it.
2. Otherwise, if the editor changed the Live date and the new date falls in
   a current or upcoming season, move the riddle to that season. The form
   says "Moved to <season> to match Live date".
3. Otherwise, keep the season. A draft with an old or placeholder Live date
   outside every current and upcoming season stays where it is.

Then the system refuses the save when:

- the season it sets is past. A riddle already in a past season keeps it,
  and cannot move to another season, by picking one or by Live date;
- the riddle will be published after the save, the save publishes it or
  changes its Live date or season, and the Live date falls outside its
  season. This covers Schedule, Reschedule and plain edits of a published
  riddle. The error names the season and its dates, so a Live date in a gap
  or a past season cannot be scheduled.

Unschedule keeps the riddle's season.

## Play flow

### Home

Home shows the **Next riddle**. Before it goes live, Home counts down to the
Live date. A ready riddle also shows how many players wait in the Lobby, and
only a ready riddle offers a way into it. A scheduled riddle shows the
countdown and a random **Practice riddle**. Once live, Home shows the time
left and how many have solved it. With no Next riddle, Home says nothing is
scheduled and also offers a Practice riddle. A player can peek at its answer
or ask for another one. A practice riddle takes no guesses and scores nothing. With
no practice riddles, Home leaves the note out.

Home, Results and the Lobby show every Live date in the display time zone
(Toronto by default, the zone admins schedule in and emails use), e.g.
"Nov 3, 1:17pm EST", or "Today at …" / "Tomorrow at …" by that zone's
date. A player whose own zone has a different UTC offset at that moment also
sees the time in their zone.

Below that, a timeline walks through a round, ending at the Next riddle's
Solve time. Home then lists riddles coming up (without their text) and, as
"Previously", the last finished riddle with its Answer and First solver.

### Lobby

The **Lobby** opens when a riddle turns ready and closes when it goes live. A
scheduled riddle has no Lobby yet. Players in the Lobby see who else is there
and a shared countdown to the Live date. When the riddle goes live, every
player in the Lobby moves to Play at the same moment.

### Notifications

Each player picks when their **Notification** comes, their **Notification
lead time**:

- *When the Lobby opens* (the default): sent when the riddle turns ready.
- *30 min* or *1 hour* before the Live date: sent at that moment, set up on
  Schedule. A Reschedule moves it; an Unschedule drops it. If that moment has
  already passed when the riddle is scheduled or rescheduled but the Live
  date is still ahead, it goes out at once.

A Notification goes by email, by text, or both: one per channel the player
turned on. Both channels use the same lead time.

The email says "Riddle No. N goes live in X minutes". It names the category and
the Live date (in the display time zone, Toronto by default) and never shows
the riddle text. If the Lobby is open it links there; if not, it says when the
Lobby opens and links to Home. Only active players with a confirmed email who
turned email on get it. The email also links to the info page (contact and
privacy).

The text fits one 160-character message: "Kriddle: Riddle No. N goes live in
X minutes.", the same link as the email, an info page link and "Reply STOP to
end".
It never shows the riddle text. Only active players with a **Confirmed
number** who turned Text on get it.

A player gets at most one email and one text per riddle. A repeat ready step,
a retry, a Reschedule or a change of lead time does not send again. Just
before sending, the system checks again: nothing goes out if the riddle was
unscheduled, its Live date has passed, or the player turned that channel off,
lost their confirmed email or number, or was banned or suspended since. An
Unschedule drops unsent Notifications, so a later Schedule can send them.

Each email has an unsubscribe link that needs no log-in. The link opens a
page with one button that turns email off. Mail clients that offer one-click
unsubscribe turn it off at once.

Every time a player turns email or Text on or off (sign-up, profile,
unsubscribe, confirming a first number, removing a number), the system logs a
**Notification consent**: the channel, granted or withdrawn, and when. The log
is only ever added to, as proof of consent.

To get texts, a player ticks Text on their profile. With no confirmed number,
ticking it shows the number step and what they agree to (rates may apply,
reply STOP to end, HELP for help, with an info page link). Confirming a first
number turns Text on. Changing to a new number keeps Text as it was. Turning
Text on sends one text that confirms it. Unticking Text pauses texts and
keeps the number.

A player can also tick Text at sign-up. They must then give a Canadian
number, and see what they agree to. Sign-up texts nothing. At their first
log-in the system texts a code to that number and links them to their
profile to type it in. Texts start only once the code checks out, as above.
The system holds the sign-up number for at most a day, and drops it at the
first log-in whether or not the text goes out. If it cannot text the number,
the link asks for a number instead.

Only Canadian numbers work. The system texts a 6-digit code; the player types it
in within 10 min and 5 tries. Only then does the number join their account as
their **Confirmed number**. A number not confirmed in time is wiped. Changing
numbers keeps the old one until the new one is confirmed. Two accounts cannot
hold the same number. Five wrong tries on a code block new codes for a day. Screens show only
its last four digits. A player gets at most 3 codes an hour, and a number at
most 5 a day. "Remove number" deletes it and turns texts off.

The text provider (AWS) blocks a number that replied STOP. A code sent to such
a number fails, and the player is told to reply START to our last text first.
The system keeps the number after STOP until the player removes it; the info
page says so.

The **info page** (`/info`, no login) tells anyone who runs Kriddle, how to
reach us, what texts we send and how to stop them, and what we keep.

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
Archive shows an empty Feed. Results links back to Home, where the Next
riddle is.

A player moved from Play to Results when the riddle completes sees one
celebration: confetti, fireworks or balloons when someone got the Win; a sad
trombone, a poof or a tumbleweed when nobody solved it. Each list takes its
turn. Opening Results any other way (Home, a link, a reload) plays nothing,
and neither does reduced motion.

A player who opens Play for a completed riddle goes to Results; for an
archived riddle, to Home.

### Standings

**Standings** rank players across all riddles, built from their saved
Solves. Anyone can see them, signed in or not; Home and Results link there.
There are four boards, each ranking by its own stat first:

| Board | Order |
|---|---|
| Points (default) | points → Wins → podiums |
| Wins | Wins → podiums → points |
| Podiums | podiums → Wins → points |
| Fastest | best solve time → earlier riddle (by Live date) |

Players level on all three share a rank (1, 2, 2, 4) and are listed A–Z.
Fastest shows each player once, with their best time on any Solve (not only
Wins) and the riddle it came from; players share a rank there only on the
same time and the same Live date. Solves with no time don't count.

A signed-in player's own row is marked. When they are on the board but
outside the top 50, their row is pinned below the list with its true rank. The
page updates by itself when a riddle completes, once its Solves are saved.
The Wins and Podiums boards leave out players with none. Each shows the
top 50. Banned and suspended players and deleted accounts are left out. A switch
picks the window: this season (the default), this month or all time. This
season counts only riddles in the current Season, by the riddle's Season
link, so each new Season starts everyone from zero. Between Seasons, this
season shows the Season that ended most recently, marked as past. Before any
Season has started, it shows "No season yet". Once two or more Seasons have
started, a season picker under this season lists the current and Past
seasons, newest first; upcoming Seasons are left out. A picked Season has its
own link (`?window=season&season=<id>`) that players can share. A Past
season's riddles never change, so its boards are final. This month counts only
riddles whose Live date falls in the current UTC calendar month. Every board
works under every window. With no Solves in the window, the page says so.

## Scoring

**Placement** is a solver's order among correct guesses, by the moment each
guess arrived. Points by placement:

| Placement | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11+ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Points | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |

A player's placement and points are fixed the moment they solve, and saved
as a Solve when the riddle completes. Totals of points, **Wins** (placement
1) and podiums (placement 1–3) are summed from Solves; nothing on the player
keeps a running count.

The first player to solve is recorded on the riddle as **First solver**, with
their time from the Live date. If two players solve at once, only one is
recorded.

At completion the riddle records its **Completion rate**, saves one
**Solve** per solver and one **Entry** per player who guessed at least once,
solvers included. The status change, the Solves and the Entries are saved
together.

## What lasts and what does not

| Kept for good | Gone at Archive (or on server restart) |
|---|---|
| Riddle, its Play and Publish status, First solver, Completion rate | Guesses and the Feed |
| Solves (placement, points, time) and Entries | Cooldowns |
| Player totals: points, wins, podiums | — |

Chat is never kept: it reaches whoever is on Results at the time and nothing
more.

## Known gaps

- **Unpublishing a live or completed riddle strands it.** Only scheduled and
  ready riddles unschedule. A live or completed riddle set to draft is saved,
  then every later step refuses it, so it never completes or archives. (#40)
- **A server restart wipes live guesses.** Placement, points, the Feed and
  Cooldowns live in memory until the riddle completes, so a restart while it
  is live loses them; no Solves get saved for that riddle.
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
- **Profile shows no totals**: no points, wins or podiums.
