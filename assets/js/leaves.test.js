import {test} from "node:test"
import assert from "node:assert/strict"
import {MAPLE, createField, isStill, leafPaths, resize, settle, step, touchesAny} from "./leaves.js"

// A seeded random, so each run spawns the same leaves.
const seeded = (seed = 1) => () => {
  seed = (seed * 16807) % 2147483647
  return (seed - 1) / 2147483646
}

test("spawns the batch above the top, spread across the whole width", () => {
  const field = createField({width: 1000, height: 600, count: 40, rand: seeded()})
  assert.equal(field.leaves.length, 40)
  assert.ok(field.leaves.every((l) => l.y < 0), "all start above the top")
  const xs = field.leaves.map((l) => l.x)
  assert.ok(Math.min(...xs) < 150 && Math.max(...xs) > 850, "they reach both edges")
})

// Runs the field for `secs` seconds at 60 frames a second.
const run = (field, secs, pointer = null) => {
  for (let i = 0; i < secs * 60; i++) step(field, 1 / 60, pointer)
  return field
}

// A field holding just the given leaves.
const fieldOf = (leaves, opts = {}) => {
  const field = createField({width: 400, height: 300, count: 0, rand: seeded(), ...opts})
  field.leaves = leaves.map((l) => ({
    vx: 0, vy: 0, size: 16, rot: 0, vr: 0, spin: 0, lie: 0, face: 1, phase: 0, shape: 0, tone: 0, resting: false, ...l,
  }))
  return field
}

test("falls and comes to rest on the floor", () => {
  const field = run(fieldOf([{x: 200, y: -20}]), 20)
  const [leaf] = field.leaves
  assert.ok(leaf.resting)
  assert.ok(leaf.y > 280 && leaf.y <= 300, `rests at the bottom, got ${leaf.y}`)
})

// A row of leaves lying across the floor, wide enough that a leaf dropped
// on it from x 200 can't slide off.
const row = () =>
  Array.from({length: 12}, (_, i) => ({x: 150 + i * 12, y: 297, resting: true}))

test("piles up: a leaf landing on others rests on top of them", () => {
  const field = run(fieldOf([...row(), {x: 200, y: 100}]), 20)
  const high = field.leaves.at(-1)
  assert.ok(high.resting)
  assert.ok(high.y < 297 - 3, `top leaf sits higher: ${high.y}`)
})

test("keeps leaves inside the width", () => {
  const field = fieldOf([{x: 1, y: 0, vx: -300}, {x: 399, y: 0, vx: 300}])
  for (let i = 0; i < 20 * 60; i++) {
    step(field, 1 / 60)
    field.leaves.forEach((l) => assert.ok(l.x >= 0 && l.x <= 400, `x ${l.x}`))
  }
})

test("a moving pointer that touches a falling leaf knocks it along", () => {
  const still = run(fieldOf([{x: 200, y: 100}]), 0.5)
  const field = fieldOf([{x: 200, y: 100}])
  step(field, 1 / 60, {x: 205, y: 100, px: 170, py: 100, vx: 900, vy: 0})
  run(field, 0.5 - 1 / 60)
  assert.ok(field.leaves[0].x > still.leaves[0].x + 40, `${field.leaves[0].x} vs ${still.leaves[0].x}`)
})

test("a pointer that passes close by but misses a falling leaf leaves it alone", () => {
  const still = run(fieldOf([{x: 200, y: 100}]), 0.5)
  const near = run(fieldOf([{x: 200, y: 100}]), 0.5, {x: 230, y: 80, px: 170, py: 80, vx: 900, vy: 0})
  assert.equal(near.leaves[0].x, still.leaves[0].x)
})

test("a pointer far away leaves falling leaves alone", () => {
  const still = run(fieldOf([{x: 200, y: 100}]), 0.5)
  const far = run(fieldOf([{x: 200, y: 100}]), 0.5, {x: 0, y: 290, vx: 900, vy: 0})
  assert.equal(far.leaves[0].x, still.leaves[0].x)
})

test("a still pointer does nothing", () => {
  const still = run(fieldOf([{x: 200, y: 100}]), 0.5)
  const parked = run(fieldOf([{x: 200, y: 100}]), 0.5, {x: 195, y: 100, vx: 0, vy: 0})
  assert.equal(parked.leaves[0].x, still.leaves[0].x)
})

const settled = () => run(fieldOf([{x: 200, y: 280}]), 5)

test("a fast pointer that touches a leaf in the pile kicks it up and along", () => {
  const field = settled()
  const [leaf] = field.leaves
  step(field, 1 / 60, {x: leaf.x, y: leaf.y, vx: 900, vy: 0})
  assert.equal(leaf.resting, false)
  assert.ok(leaf.vy < 0, "goes up")
  assert.ok(leaf.vx > 0, "goes the pointer's way")
})

test("a slow pointer leaves the pile alone", () => {
  const field = settled()
  const [leaf] = field.leaves
  step(field, 1 / 60, {x: leaf.x, y: leaf.y, vx: 60, vy: 0})
  assert.ok(field.leaves[0].resting)
})

test("a kicked leaf falls back into the pile", () => {
  const field = settled()
  const [leaf] = field.leaves
  step(field, 1 / 60, {x: leaf.x, y: leaf.y, vx: 900, vy: 0})
  run(field, 20)
  assert.ok(field.leaves[0].resting)
})

test("a leaf whose support goes falls down, rather than jumping", () => {
  const field = run(fieldOf([...row(), {x: 200, y: 100}]), 20)
  const high = field.leaves.at(-1)
  const before = high.y
  field.leaves = [high]
  step(field, 1 / 60)
  assert.equal(high.resting, false)
  assert.ok(high.y - before < 3, "no jump")
  run(field, 5)
  assert.ok(high.resting && high.y > 290, `back on the floor, at ${high.y}`)
})

test("the pile slumps: leaves dropped on one spot spread out, not up", () => {
  const drops = Array.from({length: 12}, (_, i) => ({x: 200, y: -i * 60, phase: Math.PI}))
  const field = run(fieldOf(drops), 30)
  assert.ok(field.leaves.every((l) => l.resting))
  const ys = field.leaves.map((l) => l.y)
  const xs = field.leaves.map((l) => l.x)
  assert.ok(300 - Math.min(...ys) < 16 * 0.35 * 5, `pile is ${300 - Math.min(...ys)}px tall`)
  assert.ok(Math.max(...xs) - Math.min(...xs) > 40, "and wide")
})

test("the batch is all there is: no more leaves come later", () => {
  const field = run(createField({width: 400, height: 300, count: 3, rand: seeded()}), 60)
  assert.equal(field.leaves.length, 3)
})

test("on resize, the pile moves to the new bottom and leaves stay inside the width", () => {
  const field = settled()
  resize(field, 150, 200)
  step(field, 1 / 60)
  const [leaf] = field.leaves
  assert.ok(leaf.x <= 150)
  assert.ok(leaf.resting && leaf.y > 190 && leaf.y <= 200, `on the new floor, at ${leaf.y}`)
  resize(field, 150, 500)
  run(field, 10)
  assert.ok(leaf.resting && leaf.y > 490, `falls to the lower floor, at ${leaf.y}`)
})

test("settle lays the whole batch in the pile at once", () => {
  const field = settle(createField({width: 1000, height: 600, count: 40, rand: seeded()}))
  assert.ok(field.leaves.every((l) => l.resting && l.y > 540))
})

test("is still once every leaf rests", () => {
  const field = createField({width: 400, height: 300, count: 5, rand: seeded()})
  assert.equal(isStill(field), false)
  settle(field)
  assert.equal(isStill(field), true)
})

test("draws each leaf shape as a closed outline and veins within its size", () => {
  const outlines = [0, 1, 2, 3].map((shape) => {
    const {outline, veins} = leafPaths(shape, 20)
    assert.match(outline, /^M.*Z$/)
    assert.match(veins, /^M/)
    const nums = (outline + veins).match(/-?\d+(\.\d+)?/g).map(Number)
    assert.ok(nums.every((n) => Math.abs(n) <= 14), `fits: ${nums}`)
    return outline
  })
  assert.equal(new Set(outlines).size, 4, "four different shapes")
})

test("draws a maple leaf with pointed lobes", () => {
  const {outline} = leafPaths(MAPLE, 20)
  assert.ok(outline.split("L").length > 12, "many points round its edge")
})

test("some of the leaves are maples, but not most", () => {
  const field = createField({width: 1000, height: 600, count: 200, rand: seeded(3)})
  const maples = field.leaves.filter((l) => l.shape === MAPLE).length
  assert.ok(maples > 20 && maples < 100, `${maples} maples in 200`)
})

test("a leaf lies about flat once it rests", () => {
  const field = run(fieldOf([{x: 200, y: 0, rot: 1.4, vr: 2}]), 20)
  const tilt = Math.abs(Math.sin(field.leaves[0].rot))
  assert.ok(tilt < 0.35, `tilt ${tilt}`)
})

test("a falling leaf turns gently the whole way down", () => {
  const field = createField({width: 400, height: 5000, count: 20, rand: seeded(7)})
  run(field, 4)
  const before = field.leaves.map((l) => l.rot)
  run(field, 2)
  field.leaves.forEach((l, i) => {
    const turned = Math.abs(l.rot - before[i])
    assert.equal(l.resting, false)
    assert.ok(turned > 1.5, `still turning: ${turned}`)
    assert.ok(turned < 4.5, `but gently: ${turned}`)
  })
})

test("leaves drift down gently", () => {
  const field = createField({width: 400, height: 5000, count: 20, rand: seeded(7)})
  run(field, 4)
  field.leaves.forEach((l) => assert.ok(l.vy < 65, `falls at ${l.vy}px/s`))
})

test("a pointer that comes close but misses a leaf in the pile leaves it be", () => {
  const field = settled()
  const [leaf] = field.leaves
  step(field, 1 / 60, {x: leaf.x - 20, y: leaf.y - 14, px: leaf.x - 60, py: leaf.y - 14, vx: 900, vy: 0})
  assert.ok(leaf.resting)
})

test("a quick swipe that jumps over a leaf between samples still hits it", () => {
  const field = settled()
  const [leaf] = field.leaves
  step(field, 1 / 60, {x: leaf.x + 50, y: leaf.y, px: leaf.x - 50, py: leaf.y, vx: 900, vy: 0})
  assert.equal(leaf.resting, false)
})

// Steps until the leaf lands, and gives back how fast it fell just before.
const landing = (field, leaf) => {
  let vy = leaf.vy
  for (let i = 0; i < 60 * 60 && !leaf.resting; i++) {
    vy = leaf.vy
    step(field, 1 / 60)
  }
  return vy
}

test("a leaf slows on the air just above the pile, so it lands softly", () => {
  const field = fieldOf([{x: 200, y: 0}])
  const vy = landing(field, field.leaves[0])
  assert.ok(vy < 25, `lands at ${vy}px/s`)
})

test("a landed leaf eases down flat, rather than snapping flat", () => {
  const field = fieldOf([{x: 200, y: 200, rot: 1.2}])
  const [leaf] = field.leaves
  landing(field, leaf)
  const tilt = () => Math.abs(Math.sin(leaf.rot))
  assert.ok(tilt() > 0.8, `still tilted as it touches: ${tilt()}`)
  let last = leaf.rot
  for (let i = 0; i < 60; i++) {
    step(field, 1 / 60)
    assert.ok(Math.abs(leaf.rot - last) < 0.15, "turns a little each frame")
    last = leaf.rot
  }
  assert.ok(tilt() < 0.35, `flat after a second: ${tilt()}`)
})

test("a falling leaf flutters, and shows its full face once it lands", () => {
  const field = fieldOf([{x: 200, y: 0}])
  const [leaf] = field.leaves
  const faces = []
  for (let i = 0; i < 120; i++) {
    step(field, 1 / 60)
    faces.push(leaf.face)
  }
  assert.ok(Math.min(...faces) < 0.6 && Math.max(...faces) > 0.9, "turns to and from us")
  landing(field, leaf)
  let last = leaf.face
  for (let i = 0; i < 60; i++) {
    step(field, 1 / 60)
    assert.ok(Math.abs(leaf.face - last) < 0.1, "opens a little each frame")
    last = leaf.face
  }
  assert.ok(leaf.face > 0.95, `full face: ${leaf.face}`)
})

test("is not still until landed leaves have eased flat", () => {
  const field = fieldOf([{x: 200, y: 200, rot: 1.2}])
  landing(field, field.leaves[0])
  assert.equal(isStill(field), false)
  run(field, 3)
  assert.equal(isStill(field), true)
})

test("tells whether a moving pointer touches any leaf, so a still page can sleep", () => {
  const field = settled()
  const [leaf] = field.leaves
  assert.equal(touchesAny(field, {x: leaf.x, y: leaf.y, vx: 300, vy: 0}), true)
  assert.equal(touchesAny(field, {x: leaf.x, y: leaf.y - 80, vx: 300, vy: 0}), false)
  assert.equal(touchesAny(field, {x: leaf.x, y: leaf.y, vx: 0, vy: 0}), false, "a still pointer touches nothing")
})

test("every batch comes to rest, so the loop always stops", () => {
  for (let seed = 1; seed <= 12; seed++) {
    const field = createField({width: 1000 + seed * 37, height: 700, count: 40, rand: seeded(seed)})
    run(field, 60)
    assert.ok(isStill(field), `seed ${seed} still moving after 60s`)
  }
})

test("contact means contact: a pointer just past a leaf's tip misses it", () => {
  const field = settled()
  const [leaf] = field.leaves
  const x = leaf.x + leaf.size / 2 + 3
  assert.equal(touchesAny(field, {x, y: leaf.y, vx: 300, vy: 0}), false)
})
