// Falling leaves for Home: pure physics, no DOM, so it runs under node tests.
// The `.Leaves` hook on Home draws the leaves and feeds in the pointer.

const SIZE_MIN = 10
const SIZE_MAX = 22
const SPIN_MIN = 0.9
const SPIN_RANGE = 1
const TONES = 4

/** Makes one leaf at a random spot across the width, above the top. */
export function spawnLeaf(width, rand, above = 0) {
  const size = SIZE_MIN + rand() * (SIZE_MAX - SIZE_MIN)
  // Each leaf spins one way or the other at its own pace, in rad/s.
  const spin = (rand() < 0.5 ? -1 : 1) * (SPIN_MIN + rand() * SPIN_RANGE)
  return {
    x: rand() * width,
    y: -size - rand() * above,
    vx: 0,
    vy: 0,
    size,
    rot: rand() * Math.PI * 2,
    vr: spin,
    spin,
    lie: 0,
    face: 1,
    phase: rand() * Math.PI * 2,
    shape: Math.floor(rand() * DRAWINGS.length),
    tone: Math.floor(rand() * TONES),
    resting: false,
  }
}

/**
 * Makes a field with `count` leaves staggered above the top, so they reach
 * the page one after another. They are all that ever fall.
 */
export function createField({width, height, count, rand = Math.random}) {
  const leaves = Array.from({length: count}, () => spawnLeaf(width, rand, height * 0.8))
  return {width, height, rand, leaves}
}

/** Fits the field to a new size. Leaves keep their place inside it. */
export function resize(field, width, height) {
  field.width = width
  field.height = height
  for (const leaf of field.leaves) leaf.x = Math.min(width, leaf.x)
  return field
}

// Falling: a leaf drifts toward its top speed (bigger leaves fall faster)
// and sways side to side as it goes.
const FALL_SPEED = 28
const FALL_PER_PX = 1.5
const DRAG = 1.6
const SWAY = 22
const SWAY_RATE = 1.3

// How far edge on a fluttering leaf turns: its face shrinks to this share.
const FLUTTER = 0.4

// How fast a landed leaf settles flat: the share of the way it goes each
// second.
const EASE = 4

// Within CUSHION px of the pile a leaf slows, down to SOFTEST of its top
// speed as it touches.
const CUSHION = 40
const CUSHION_PULL = 5
const SOFTEST = 0.25

// How thick a leaf lying in the pile is, as a share of its size.
const THICKNESS = 0.35

const fallSpeed = (leaf) => FALL_SPEED + leaf.size * FALL_PER_PX
const halfThick = (leaf) => (leaf.size * THICKNESS) / 2

// The pile is a height map: how high it stands in each BIN-wide column.
const BIN = 4

// The columns a leaf lying flat covers, as [first, last].
function span(field, leaf) {
  const cols = Math.ceil(field.width / BIN)
  const half = (leaf.size * 0.8) / 2
  const first = Math.max(0, Math.floor((leaf.x - half) / BIN))
  const last = Math.min(cols - 1, Math.floor((leaf.x + half) / BIN))
  return [first, Math.max(first, last)]
}

function topOf(pile, [first, last]) {
  let top = 0
  for (let c = first; c <= last; c++) top = Math.max(top, pile[c])
  return top
}

// Where a leaf would lie on the pile under it.
const restY = (field, pile, leaf) =>
  field.height - topOf(pile, span(field, leaf)) - halfThick(leaf)

// Lays a leaf on the pile and raises the pile under it.
function lay(field, pile, leaf) {
  const cols = span(field, leaf)
  const top = topOf(pile, cols) + leaf.size * THICKNESS
  for (let c = cols[0]; c <= cols[1]; c++) pile[c] = top
  leaf.y = field.height - top + halfThick(leaf)
}

// A leaf that lands on a slope slides down it at SLIDE px/s, so the pile
// slumps into a heap rather than a tower.
const SLIDE = 90

// -1 or 1 when the pile drops away more than a leaf's thickness to that
// side of a leaf, else 0.
function downhill(field, pile, leaf) {
  const off = leaf.size * 0.6
  const here = restY(field, pile, leaf)
  const at = (x) => (x < 0 || x > field.width ? 0 : restY(field, pile, {...leaf, x}) - here)
  const left = at(leaf.x - off)
  const right = at(leaf.x + off)
  const drop = leaf.size * THICKNESS * 0.8
  if (Math.max(left, right) <= drop) return 0
  return left > right ? -1 : 1
}

// Builds the pile from the resting leaves, bottom up. A leaf left hanging,
// because the leaf under it went, falls again.
function buildPile(field) {
  // The height map and the list of lying leaves are kept on the field and
  // reused, so a frame makes no garbage.
  const cols = Math.ceil(field.width / BIN)
  if (field.pile?.length !== cols) field.pile = new Float32Array(cols)
  const pile = field.pile.fill(0)
  const lying = (field.lying ||= [])
  lying.length = 0
  for (const leaf of field.leaves) if (leaf.resting) lying.push(leaf)
  lying.sort((a, b) => b.y - a.y)
  for (const leaf of lying) {
    if (leaf.y < restY(field, pile, leaf) - 1) leaf.resting = false
    else lay(field, pile, leaf)
  }
  return pile
}

// A moving pointer that touches a falling leaf knocks it along: the leaf
// takes BUMP of the pointer's speed.
const BUMP = 0.6

const moving = (pointer) => pointer && (pointer.vx !== 0 || pointer.vy !== 0)

// A pointer that touches a leaf in the pile, faster than KICK px/s, throws
// it up out of the pile, along its way.
const KICK = 80
const LIFT = 0.45

// True when the pointer's path since its last move (px, py to x, y) passes
// over the leaf, so a quick swipe can't jump a leaf between samples.
function touches(pointer, leaf) {
  const ax = pointer.px ?? pointer.x
  const ay = pointer.py ?? pointer.y
  const dx = pointer.x - ax
  const dy = pointer.y - ay
  const len = dx * dx + dy * dy
  const t = len === 0 ? 0 : Math.max(0, Math.min(1, ((leaf.x - ax) * dx + (leaf.y - ay) * dy) / len))
  const d = Math.hypot(leaf.x - (ax + t * dx), leaf.y - (ay + t * dy))
  return d <= leaf.size / 2
}

/** True when a moving pointer touches any leaf, falling or in the pile. */
export const touchesAny = (field, pointer) =>
  moving(pointer) && field.leaves.some((leaf) => touches(pointer, leaf))

function kick(leaf, pointer) {
  const speed = Math.hypot(pointer.vx, pointer.vy)
  leaf.resting = false
  leaf.vx = pointer.vx * 0.7
  leaf.vy = -(60 + speed * LIFT)
  leaf.vr = leaf.spin + pointer.vx / 120
}

/** True once every leaf rests in the pile and has eased flat. */
export const isStill = (field) =>
  field.leaves.every(
    (l) => l.resting && Math.abs(l.lie - l.rot) < 0.01 && l.face > 0.99,
  )

/**
 * Lets the leaves in the air fall into the pile at once, for players who
 * ask for less motion.
 */
export function settle(field) {
  for (let i = 0; i < 20000 && !isStill(field); i++) step(field, 1 / 30)
  return field
}

/**
 * Moves the field on by `dt` seconds. `pointer` is `{x, y, px, py, vx, vy}`
 * in px and px/s, with px, py where it was before its last move; or null.
 */
export function step(field, dt, pointer = null) {
  const fast = pointer && Math.hypot(pointer.vx, pointer.vy) > KICK
  for (const leaf of field.leaves) {
    if (leaf.resting && fast && touches(pointer, leaf)) kick(leaf, pointer)
  }

  const pile = buildPile(field)

  const ease = Math.min(1, EASE * dt)
  for (const leaf of field.leaves) {
    if (leaf.resting) {
      leaf.rot += (leaf.lie - leaf.rot) * ease
      leaf.face += (1 - leaf.face) * ease
      continue
    }
    const pull = Math.min(1, DRAG * dt)
    // Just above the pile the air holds a leaf up, so it lands softly.
    const gap = restY(field, pile, leaf) - leaf.y
    if (gap < CUSHION && leaf.vy > 0) {
      const soft = fallSpeed(leaf) * Math.max(SOFTEST, gap / CUSHION)
      leaf.vy += (soft - leaf.vy) * Math.min(1, CUSHION_PULL * dt)
    } else {
      leaf.vy += (fallSpeed(leaf) - leaf.vy) * pull
    }
    leaf.vx -= leaf.vx * pull
    // A bump or a kick can spin a leaf up; it eases back to its own spin.
    leaf.vr += (leaf.spin - leaf.vr) * pull * 0.5
    if (moving(pointer) && touches(pointer, leaf)) {
      leaf.vx += (pointer.vx - leaf.vx) * BUMP
      leaf.vy += (pointer.vy - leaf.vy) * BUMP
      leaf.vr += (pointer.vx / 200) * BUMP
    }
    leaf.phase += SWAY_RATE * dt
    // As it falls a leaf flutters, turning its face to and from us: 1 is
    // full on, less is edge on.
    leaf.face = FLUTTER + (1 - FLUTTER) * Math.abs(Math.cos(leaf.phase * 1.3))
    leaf.x += (leaf.vx + Math.sin(leaf.phase) * SWAY) * dt
    leaf.y += leaf.vy * dt
    leaf.rot += leaf.vr * dt
    // The sides bounce a leaf back in.
    if (leaf.x < 0 || leaf.x > field.width) {
      leaf.x = Math.min(field.width, Math.max(0, leaf.x))
      leaf.vx = -leaf.vx * 0.5
    }

    if (leaf.vy > 0 && leaf.y >= restY(field, pile, leaf)) {
      const dir = downhill(field, pile, leaf)
      if (dir === 0) {
        leaf.vx = leaf.vy = leaf.vr = 0
        // It will ease down flat, give or take a little, whichever way round
        // is nearer.
        leaf.lie = Math.round(leaf.rot / Math.PI) * Math.PI + (field.rand() - 0.5) * 0.5
        leaf.resting = true
        lay(field, pile, leaf)
      } else {
        leaf.x = Math.min(field.width, Math.max(0, leaf.x + dir * SLIDE * dt))
        leaf.y = restY(field, pile, leaf)
      }
    }
  }
  return field
}

// Leaf drawings on a unit leaf, tip to stem along x from 0.5 to -0.5,
// drawn loose like the other doodles. An almond, a slim willow and a round
// birch are two curves each, with a stem, midrib and three veins. A maple is
// a ring of pointed lobes, with a stem and a vein out to each big lobe.
const LEAF_VEINS = [
  [[-0.68, 0.04], [0.4, 0]],
  [[-0.2, 0], [-0.05, -0.15]],
  [[0.1, 0], [0.22, -0.11]],
  [[-0.05, 0], [0.1, 0.14]],
]
const DRAWINGS = [
  {curve: [[-0.5, 0], [-0.2, -0.38], [0.25, -0.32], [0.5, 0], [0.25, 0.32], [-0.2, 0.38]], veins: LEAF_VEINS},
  {curve: [[-0.5, 0], [-0.15, -0.22], [0.2, -0.2], [0.5, 0], [0.2, 0.2], [-0.15, 0.22]], veins: LEAF_VEINS},
  {curve: [[-0.45, 0], [-0.42, -0.46], [0.2, -0.44], [0.5, 0], [0.2, 0.44], [-0.42, 0.46]], veins: LEAF_VEINS},
  {
    points: [
      [-0.32, 0.04], [-0.4, 0.3], [-0.18, 0.22], [-0.05, 0.48], [0.02, 0.3], [0.22, 0.36],
      [0.12, 0.14], [0.34, 0.16], [0.5, 0], [0.34, -0.16], [0.12, -0.14], [0.22, -0.36],
      [0.02, -0.3], [-0.05, -0.48], [-0.18, -0.22], [-0.4, -0.3], [-0.32, -0.04],
    ],
    veins: [
      [[-0.62, 0.03], [0.38, 0]],
      [[-0.26, 0], [-0.05, 0.36]],
      [[-0.26, 0], [-0.05, -0.36]],
    ],
  },
]

/** The shape number of the maple, the one leaf drawn as lobes. */
export const MAPLE = 3

/**
 * The leaf `shape` (0-3, see MAPLE) at `size` px long, centred on 0,0, as
 * SVG path data: the outline (closed) and the stem and veins.
 */
export function leafPaths(shape, size) {
  const p = ([x, y]) => `${+(x * size).toFixed(1)} ${+(y * size).toFixed(1)}`
  const {curve, points, veins} = DRAWINGS[shape % DRAWINGS.length]
  let outline
  if (points) {
    outline = `M${points.map(p).join(" L")} Z`
  } else {
    const [start, c1, c2, tip, c3, c4] = curve
    outline = `M${p(start)} C${p(c1)} ${p(c2)} ${p(tip)} C${p(c3)} ${p(c4)} ${p(start)} Z`
  }
  return {outline, veins: veins.map(([a, b]) => `M${p(a)} L${p(b)}`).join(" ")}
}
