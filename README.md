# Riddlr

Riddlr is a real-time multiplayer riddle game. Admins author riddles and schedule them to go live at a specific wall-clock time. Players gather in a lobby, watch a shared countdown, then race to be first to submit the correct answer.

Tech stack: Phoenix 1.8 / LiveView 1.2, plain Ecto + Postgres, Oban for lifecycle jobs, PubSub + Presence for realtime, ETS for ephemeral round state.
