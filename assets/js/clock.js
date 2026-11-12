// The countdown clock formats. Mirrors the clock functions in
// lib/riddlr_web/components/game_components/clock.ex (clock_groups/1,
// clock_str/1, clock_spoken/1). Change both together; the two test files
// share one table of cases.

const DAY = 86400

const pad = (n) => String(n).padStart(2, "0")

const split = (secs) => {
  secs = Math.max(0, secs)
  return [
    Math.floor(secs / DAY),
    Math.floor((secs % DAY) / 3600),
    Math.floor((secs % 3600) / 60),
    secs % 60,
  ]
}

const plural = (n, word) => (n === 1 ? word : `${word}s`)

const unit = (n, word) => `${n} ${plural(n, word)}`

// The clock's digit groups, each as [digits, unit word or null]. From one day
// up: days, hours, minutes, labelled ("day", "hour", "min" for one). Under a day: HH, MM, SS or MM, SS.
export const clockGroups = (secs) => {
  const [d, h, m, s] = split(secs)
  if (d > 0) return [[pad(d), plural(d, "day")], [pad(h), plural(h, "hour")], [pad(m), plural(m, "min")]]
  if (h > 0) return [[pad(h), null], [pad(m), null], [pad(s), null]]
  return [[pad(m), null], [pad(s), null]]
}

// MM:SS, HH:MM:SS from one hour up, or DD:HH:MM from one day up.
export const clockStr = (secs) => clockGroups(secs).map(([digits]) => digits).join(":")

// e.g. "6 days, 20 hours, 48 minutes" from one day up, or clockStr below.
export const clockSpoken = (secs) => {
  const [d, h, m] = split(secs)
  return d > 0 ? [unit(d, "day"), unit(h, "hour"), unit(m, "minute")].join(", ") : clockStr(secs)
}
