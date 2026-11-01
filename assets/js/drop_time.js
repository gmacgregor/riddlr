// Text for the "your local time" line under a drop time.
//
// The server renders drop times in the display zone (Eastern). A player whose
// browser zone has a different UTC offset at the drop instant also gets the
// time in their own zone. Offsets, not zone names, decide: New York and
// Toronto count as the same.
//
// Kept free of the DOM so `node --test` can run it.

const parts = (date, timeZone, options) =>
  Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {timeZone, ...options})
      .formatToParts(date)
      .map(({type, value}) => [type, value]),
  )

// Minutes east of UTC for `zone` at `date`.
function offset(date, zone) {
  const {year, month, day, hour, minute} = parts(date, zone, {
    year: "numeric", month: "numeric", day: "numeric",
    hour: "numeric", minute: "numeric", hourCycle: "h23",
  })
  const wall = Date.UTC(year, month - 1, day, hour, minute)
  return Math.round((wall - Math.floor(date.getTime() / 60000) * 60000) / 60000)
}

// Days since the epoch for the calendar date `date` falls on in `zone`.
function dayNumber(date, zone) {
  const {year, month, day} = parts(date, zone, {year: "numeric", month: "numeric", day: "numeric"})
  return Date.UTC(year, month - 1, day) / 86400000
}

/**
 * The drop time in `browserZone`, or null when that zone's offset matches
 * `displayZone`'s at the drop instant.
 *
 * Reads "Mon, Nov 3, 10:17am PST", or "Today at …" / "Tomorrow at …" by the
 * browser's date at `now`.
 */
export function localDropText(instant, browserZone, displayZone, now = new Date()) {
  const at = new Date(instant)
  if (offset(at, browserZone) === offset(at, displayZone)) return null

  const {weekday, month, day, hour, minute, dayPeriod, timeZoneName} = parts(at, browserZone, {
    weekday: "short", month: "short", day: "numeric",
    hour: "numeric", minute: "2-digit", hour12: true, timeZoneName: "short",
  })
  const time = `${hour}:${minute}${dayPeriod.toLowerCase()} ${timeZoneName}`

  switch (dayNumber(at, browserZone) - dayNumber(now, browserZone)) {
    case 0: return `Today at ${time}`
    case 1: return `Tomorrow at ${time}`
    default: return `${weekday}, ${month} ${day}, ${time}`
  }
}
