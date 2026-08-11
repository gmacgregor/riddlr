# Riddlr — Context

Real-time multiplayer riddle game. Admins schedule riddles to go live at a
wall-clock time; players race in a shared lobby to answer first.

Deep dive: `docs/DOMAIN.md`. Lifecycle detail: `docs/RIDDLE_LIFECYCLE.md`.

## Glossary

| Term | Meaning |
|---|---|
| **Riddle** | The central aggregate and the unit of play. One riddle = one game. |
| **Category** | Taxonomy a riddle belongs to. |
| **Answer** | A player submission (`Riddlr.Gameplay.Answer`). Ephemeral — lives in ETS, never persisted. |
| **Play status** | Riddle's lifecycle state: `closed → scheduled → ready → live → completed → archived`. |
| **Publish status** | Orthogonal `draft`/`published`. Unpublished riddles never transition. |
| **Live date** | Wall-clock instant a riddle goes `live`. |
| **Solve time** | Seconds a live riddle stays open before auto-completing. |
| **Lobby** | Pre-game waiting room with presence + shared countdown. |
| **Placement** | A solver's race order among correct answers. Drives points. |
| **First solver** | Placement 1. Recorded on the riddle; the concurrency gate for completion. |
| **Podium** | Placements 1–3. |
| **Cooldown** | 1s per-user submit rate limit (UX only, non-atomic). Also the post-completion window before archive. |
| **Archive** | Terminal state. Drops the riddle's ETS rows. |
| **Clock** | The port every time read goes through (`Riddlr.Clock`). Frozen in tests; nothing else reads the runtime clock. |
| **Game clock** | A riddle's countdown (`Riddlr.GameClock`). One process per riddle broadcasting a tick a second, in two phases: `:lobby` counts to the Live date, `:play` counts down the Solve time. All players see the same value at the same moment. |

Avoid: "round"/"turn" (there are none — one riddle is one simultaneous race),
"question" (say **riddle**), "score" as a verb for placement (say **award points**).
