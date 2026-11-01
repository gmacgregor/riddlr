# 1. Notification consent log

Date: 2026-11-01

## Status

Accepted

## Context

Canada's anti-spam law (CASL) asks us to prove a player agreed to get
Notifications. The `users.notify_email` flag only shows the current choice,
not when the player made it or what came before. Text (SMS) Notifications are
coming, and they need the same proof.

## Decision

Keep an append-only `notification_consents` table. Each time a player turns a
channel on or off we add one row: `user_id`, `channel` (`email` or `sms`),
`action` (`granted` or `withdrawn`) and `inserted_at`.

- The row commits in the same transaction as the `users` change, so the flag
  and the log never disagree.
- A save that does not change the flag adds no row.
- Code has no path to update or delete a row. Rows go only when their player
  is deleted.
- Sign-up, the profile form and one-click unsubscribe all write rows.
- Players who opted in before the log shipped get no backfilled row.

We keep the fields bare: no IP address, user agent or copy of the consent
wording. The wording a player saw is the form copy in git at the time of the
row's `inserted_at`, so git history is the record of what they agreed to.

## Consequences

- We can show when each player granted or withdrew consent, per channel.
- To prove the exact wording, read the form templates in git as of the row's
  date. A wording change must go through a commit, never a runtime setting.
- Players who opted in before the log have no row; their consent rests on
  the sign-up form of that time.
- The table only grows. At one row per change this stays small.
