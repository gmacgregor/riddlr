import {test} from "node:test"
import assert from "node:assert/strict"
import {clockGroups, clockShort, clockSpoken, clockStr} from "./clock.js"

// The same cases as the clock tests in game_components_test.exs, so the
// Elixir and JS formats agree.
test("clockStr shows MM:SS under an hour", () => {
  assert.equal(clockStr(0), "00:00")
  assert.equal(clockStr(45), "00:45")
  assert.equal(clockStr(3599), "59:59")
})

test("clockStr shows HH:MM:SS from one hour up", () => {
  assert.equal(clockStr(3600), "01:00:00")
  assert.equal(clockStr(86399), "23:59:59")
})

test("clockStr shows DD:HH:MM from one day up", () => {
  assert.equal(clockStr(86400), "01:00:00")
  assert.equal(clockStr(90061), "01:01:01")
  assert.equal(clockStr(593308), "06:20:48")
  assert.equal(clockStr(12 * 86400 + 59), "12:00:00")
  assert.equal(clockStr(100 * 86400), "100:00:00")
})

test("clockStr treats negative seconds as zero", () => {
  assert.equal(clockStr(-3), "00:00")
})

test("clockGroups labels the groups from one day up", () => {
  assert.deepEqual(clockGroups(593308), [["06", "days"], ["20", "hours"], ["48", "mins"]])
})

test("clockGroups uses the singular unit for a count of one", () => {
  assert.deepEqual(clockGroups(90061), [["01", "day"], ["01", "hour"], ["01", "min"]])
})

test("clockGroups leaves the groups unlabelled under a day", () => {
  assert.deepEqual(clockGroups(86399), [["23", null], ["59", null], ["59", null]])
  assert.deepEqual(clockGroups(125), [["02", null], ["05", null]])
})

test("clockShort reads as days, hours and minutes from one day up", () => {
  assert.equal(clockShort(593308), "6d 20h 48m")
  assert.equal(clockShort(86400), "1d 0h 0m")
})

test("clockShort reads as the clock under a day", () => {
  assert.equal(clockShort(86399), "23:59:59")
  assert.equal(clockShort(125), "02:05")
})

test("clockSpoken spells out the units from one day up", () => {
  assert.equal(clockSpoken(593308), "6 days, 20 hours, 48 minutes")
  assert.equal(clockSpoken(90061), "1 day, 1 hour, 1 minute")
})

test("clockSpoken reads as the clock under a day", () => {
  assert.equal(clockSpoken(125), "02:05")
})
