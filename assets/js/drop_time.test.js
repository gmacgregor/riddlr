import {test} from "node:test"
import assert from "node:assert/strict"
import {localDropText} from "./drop_time.js"

const TORONTO = "America/Toronto"
// Fixed UTC-8 with no DST. Real zones like Vancouver can change their rules
// in new tz data, which breaks tests dated in the future.
const FIXED_MINUS_8 = "Etc/GMT+8"
// Eastern noon on 2030-01-01, so drops on later days read as dates.
const NOW = new Date("2030-01-01T17:00:00Z")

test("gives nothing when the browser zone has the same offset", () => {
  assert.equal(localDropText("2030-01-08T18:17:00Z", TORONTO, TORONTO, NOW), null)
  assert.equal(localDropText("2030-01-08T18:17:00Z", "America/New_York", TORONTO, NOW), null)
})

test("gives the local time when the offset differs", () => {
  assert.equal(
    localDropText("2030-01-08T18:17:00Z", FIXED_MINUS_8, TORONTO, NOW),
    "Tue, Jan 8, 10:17am GMT-8",
  )
})

test("judges the offset at the drop instant, not today", () => {
  // London moves to summer time on Mar 31 2030, Toronto on Mar 10. Between
  // them the gap is 4 hours, not 5, but the offsets still differ.
  assert.equal(
    localDropText("2030-03-20T17:00:00Z", "Europe/London", TORONTO, NOW),
    "Wed, Mar 20, 5:00pm GMT",
  )
  // Bogota stays on UTC-5 all year: it matches EST in winter, not EDT in summer.
  assert.equal(localDropText("2030-01-08T18:17:00Z", "America/Bogota", TORONTO, NOW), null)
  assert.equal(
    localDropText("2030-07-08T17:17:00Z", "America/Bogota", TORONTO, NOW),
    "Mon, Jul 8, 12:17pm GMT-5",
  )
})

test("says Today or Tomorrow by the browser's date", () => {
  assert.equal(
    localDropText("2030-01-01T18:17:00Z", FIXED_MINUS_8, TORONTO, NOW),
    "Today at 10:17am GMT-8",
  )
  assert.equal(
    localDropText("2030-01-02T18:17:00Z", FIXED_MINUS_8, TORONTO, NOW),
    "Tomorrow at 10:17am GMT-8",
  )
})

test("uses the browser's date even where it differs from Eastern", () => {
  // 9pm Eastern on Jan 1 is 11am Jan 2 in Tokyo; at Eastern noon Jan 1 it
  // is already 2am Jan 2 in Tokyo, so the drop is today there.
  assert.equal(
    localDropText("2030-01-02T02:00:00Z", "Asia/Tokyo", TORONTO, NOW),
    "Today at 11:00am GMT+9",
  )
})
