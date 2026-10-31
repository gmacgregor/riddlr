# Riddlr

Real-time multiplayer riddle game. Admins schedule riddles to go live at a set
time; players wait in a shared lobby, then race to answer first.

How it all works: [`docs/DOMAIN.md`](docs/DOMAIN.md).

## People

**Player**:
Anyone signed in who plays riddles. Every account is a player.

**Admin**:
A super admin, moderator or editor: anyone who can reach the admin pages.

**Super admin**:
Can do everything: manage riddles and users, moderate, ban players, see stats.

**Editor**:
An admin who writes and schedules riddles and categories.

**Moderator**:
An admin who moderates guesses, bans players and sees stats. Cannot manage riddles.

**Viewer**:
Can see stats only. Not an admin.

## Riddles

**Riddle**:
The unit of play. One riddle is one game: every player races at the same time.
_Avoid_: question, round, turn, game (as a separate thing)

**Category**:
The group a riddle belongs to.

**Riddle number**:
The public "No. N" of a riddle, given once when the riddle is created.

**Answer**:
A string an admin accepts as correct for a riddle. A riddle has one or more; matching ignores case and outer spaces.
_Avoid_: solution

**Hint**:
Optional help text an admin attaches to a riddle, meant to show after a set delay. Not yet shown to players.

**Practice riddle**:
A riddle and answer shown on Home while nothing is scheduled. It takes no guesses and awards no points.
_Avoid_: sample, demo riddle

## Lifecycle

**Play status**:
Where a riddle is in its life: closed → scheduled → ready → live → completed → archived.
_Avoid_: state, phase

**Publish status**:
Draft or published, set apart from Play status. Only a published riddle can move to a new Play status.

**Live date**:
The moment a riddle goes live.
_Avoid_: start time, launch time

**Ready window**:
How long before the Live date a riddle turns ready.

**Solve time**:
How long a live riddle takes guesses. It always runs to the end, however soon the first solve comes.
_Avoid_: time limit, duration

**Post-game**:
The time between completed and archived, when players see results and chat.
_Avoid_: cooldown, archive delay

**Schedule**:
Publishing a closed riddle with a future Live date, so it will go ready and live by itself.

**Reschedule**:
Moving the Live date or Ready window of a scheduled or ready riddle.

**Unschedule**:
Setting a scheduled or ready riddle back to draft, which returns it to closed.
_Avoid_: cancel, draft rollback

**Archive**:
The last Play status. The riddle takes no more guesses and its live feed is gone; its solves stay.

**Next riddle**:
The published riddle players can join next: the live one, or else the scheduled or ready one with the soonest Live date.

## Play

**Lobby**:
The waiting room before a riddle goes live, with who is present and a shared countdown.

**Game clock**:
A riddle's shared countdown. It counts to the Live date in the Lobby, then down the Solve time in play. Every player sees the same value at the same moment.
_Avoid_: timer

**Guess**:
What a player submits to a live riddle. Lives only until Archive.
_Avoid_: answer, submission, attempt

**Cooldown**:
The 1s wait between one player's guesses. A convenience, not a security control.
_Avoid_: rate limit

**Feed**:
The live stream of every player's guesses. The text of a correct guess is hidden until Post-game.

**Chat**:
Messages players post in Post-game, shown beside the Leaderboard.

**Flag**:
Moderation marking a guess as unfit; it disappears from every Feed.

**Ban**:
Barring a player from guessing.

## Results

**Solve**:
One player's correct guess at a riddle, kept for good once the riddle completes: placement, points and solve time.

**Placement**:
A solver's finishing order among correct guesses.
_Avoid_: rank, position

**Points**:
What a placement earns: 10 for 1st down to 1 for 10th, 0 after.
_Avoid_: score (as a verb — say **award points**)

**Win**:
Placement 1 on a riddle. A player's wins and podiums are counted across all riddles.

**First solver**:
The player who got the Win, recorded on the riddle.

**Podium**:
Placements 1–3.

**Completion rate**:
Share of players who guessed a riddle that also solved it.

**Leaderboard**:
A riddle's solves in placement order, shown on its results page.
