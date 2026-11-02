# 2. Phone storage and confirmation

Date: 2026-11-01

## Status

Accepted

## Context

Players can add a Canadian mobile number to get text Notifications (#59,
#66). A phone number is personal data. We must text it, so we need the real
number back, not just a way to check it. We must also:

- stop two accounts holding the same number,
- find a player by number when a STOP reply comes in (#69),
- keep the number out of logs, job args and error text,
- keep only numbers the player has proved they own, apart from a number
  given at sign-up, held a short time (see below).

## Decision

### Encrypt the number, index it with an HMAC

- `users.phone` and `phone_codes.phone` hold the E.164 number encrypted with
  AES-256-GCM (`cloak_ecto`, `Riddlr.Vault`). The key comes from `CLOAK_KEY`.
  Each value names its key by tag, so we can rotate: add the new key first,
  keep the old one to decrypt, re-encrypt, drop the old key. `CLOAK_KEY_TAG`
  names the current key and is required; `CLOAK_KEY_OLD_TAG` names the old
  one. Values written while the tag had a default carry `AES.GCM.V1`, so one
  of the two tags must be `AES.GCM.V1` while those values remain.
- `phone_hash` holds HMAC-SHA256 of the E.164 number (`Riddlr.Hashed.HMAC`), a
  blind index. The secret comes from a separate env var, `PHONE_HMAC_KEY`, so
  a leak of one key does not give away the other.
- `users.phone_hash` has a unique index, so two accounts cannot hold the same
  number. STOP replies find the player by this hash.
- Both fields are `redact: true`. Screens show the last four digits only,
  admin screens too. Logs, Oban args and errors never carry the number;
  Phoenix filters `phone` and `code` params from request logs.

**Why not a password-style hash (bcrypt, Argon2)?** We must send texts, so we
need the number back; a one-way hash cannot give it. A salted slow hash also
cannot back a unique index or a lookup by number, since each salt gives a
new hash. HMAC is fast, but there are only about 10^10 Canadian numbers, so
any unkeyed hash of a number can be brute-forced. The HMAC secret is what
stops that, which is why it lives apart from the database.

### A number reaches the account only once confirmed

- "Text me a code" writes a `phone_codes` row: the pending number (encrypted),
  its hash, a SHA-256 of a random 6-digit code, a try count and the send time.
  `users` does not change.
- The right code within 10 minutes and 5 tries copies the number onto
  `users`, sets `phone_confirmed_at`, and wipes the number and code from the
  row, in one transaction.
- A player changing a confirmed number keeps the old one live until the new
  one is confirmed. Then the new number replaces it.
- Only the newest code works. Once a new text goes out, the number and code
  are wiped from the player's older rows. A text that fails wipes its own
  row instead, so the earlier code keeps working.
- Sending a code to a number another account holds is refused before we
  text it. The refusal counts toward the hourly send limit, so players
  cannot probe which numbers are taken. The unique index also catches a race
  at confirm.
- A number need not be confirmed to be pending, so a pending number never
  blocks its owner from adding it on their own account.

### Send limits

- 3 codes per player per hour and 5 per number per day, across accounts.
  Counted from `phone_codes` rows.
- A code that gets 5 wrong tries blocks new codes for that player for 24
  hours from when it was sent (so up to 10 minutes less than 24 hours after
  the last try). The used try count stays on the row through Remove number.
  Both limits and the block count rows by send time, so a late prune does
  not stretch them. The player's row and an advisory lock on
  the number are held while counting, so two sends at once, from one account
  or several, cannot both pass. Failed texts count too.

### A number given at sign-up (#68)

- Ticking Text at sign-up needs a Canadian number. It goes, encrypted, in
  `users.signup_phone`, with `users.text_requested` set. No hash: sign-up
  does not check whether the number is taken, so it cannot be used to probe
  numbers with no limit.
- Sign-up texts nothing and logs no consent.
- The first log-in takes the number off the locked user row, so two log-ins
  at once text it only once, then sends a code as "Text me a code" does.
  Limits and the taken-number check apply. The number is gone from `users`
  whatever the result; if the text did not go, the player adds a number on
  `/profile`.
- Texts start, and consent is logged, only when the code checks out.
- `text_requested` holds no number. It pre-ticks Text on `/profile` and is
  cleared by confirming a number, Remove number or a saved notification
  change.

### Retention

- An Oban cron job (`PrunePhoneCodesWorker`, every hour) wipes the number
  and code from rows whose code has expired, deletes rows older than a day,
  and wipes `signup_phone` from accounts more than a day old. So an
  unconfirmed number lasts at most about 70 minutes, and a sign-up number at
  most about 25 hours. A code still fails after 10 minutes between runs: the
  check reads the send time, not the prune.
- A row's `phone_hash` stays up to a day after its code expires, for the
  per-number limit. It cannot be turned back into the number without the
  HMAC secret.
- Unticking Text (#67) pauses texts and keeps the number.
- "Remove number" wipes `phone`, `phone_hash`, `phone_confirmed_at` and
  `signup_phone` on `users`, sets `notify_sms = false` and
  `text_requested = false`, and clears the number, hash and code
  from all the player's `phone_codes` rows. The empty rows stay, up to a day,
  so they still count toward the hourly send limit.
- A STOP reply (#69) does the same as Remove number.

### Texting off until a provider is set

- `Riddlr.SMS` sends through the adapter in `config :riddlr, Riddlr.SMS`.
  Dev uses `Local` (logs the text with the last four digits only); test uses
  `Test`. Prod has none until `SMS_ADAPTER` is set (#69).
- With no adapter, `/profile` hides the phone section and refuses every phone
  step except Remove number. Sign-up hides Text and ignores a Text opt-in.

## Consequences

- A database dump shows no readable numbers. Reading one needs `CLOAK_KEY`.
- Losing `CLOAK_KEY` loses every stored number. Changing `PHONE_HMAC_KEY`
  breaks the unique index and STOP lookups until every hash is rebuilt.
- A sign-up number (#68) sits unconfirmed on `users` for up to about a day,
  the one place an unproved number lives longer than a code. It is encrypted
  and never texted before the first log-in. Someone could sign up with
  another person's number; that person gets at most one code, at the first
  log-in, under the usual limits.
- Hourly pruning keeps unconfirmed numbers up to about an hour longer than a
  per-minute job would. We accept this for fewer jobs.
- A code is 6 digits with 5 tries: a 1 in 200,000 chance to guess per code.
  The send limits cap how many codes one player can try.
- Remove number wipes the hash from the player's sent-code rows, so it also
  resets the per-number daily count. Someone with several accounts could add
  and remove a number to text it more than 5 times a day; each account is
  still capped at 3 an hour. We accept this to keep Remove number complete.
