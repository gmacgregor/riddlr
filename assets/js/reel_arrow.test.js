import {test} from "node:test"
import assert from "node:assert/strict"
import {reelArrowPath} from "./reel_arrow.js"

const points = (d) => d.match(/-?\d+(\.\d+)?/g).map(Number)

test("starts at the top left and ends at the bottom right", () => {
  const d = reelArrowPath(400, 200)
  assert.match(d, /^M0 0 /)
  assert.match(d, /C[^M]* 400 200 M/)
})

test("draws the head as two strokes meeting at the end", () => {
  const d = reelArrowPath(400, 200)
  const head = d.slice(d.lastIndexOf("M"))
  const [x1, y1, x2, y2, x3, y3] = points(head)
  assert.deepEqual([x2, y2], [400, 200])
  assert.ok(y1 < 200 && y3 < 200, "both strokes come down into the tip")
  assert.ok(x1 < 400 && x3 > 400, "one stroke on each side")
})

test("keeps the head the same size whatever the arrow's size", () => {
  const head = (d) => points(d.slice(d.lastIndexOf("M")))
  const [a1, , a2] = head(reelArrowPath(300, 120))
  const [b1, , b2] = head(reelArrowPath(700, 260))
  assert.equal(a2 - a1, b2 - b1)
})
