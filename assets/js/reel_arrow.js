// The pen arrow between two Home timeline steps, in real pixels so it never
// stretches. It runs down from the top left, swings across the last stretch
// and drops into the bottom right, where two short strokes make the head.
// Even rows mirror the drawing in CSS.

const HEAD_W = 7
const HEAD_H = 9
const SWING = 72

const r = (n) => Math.round(n * 10) / 10

export function reelArrowPath(w, h) {
  const s = Math.min(h * 0.7, SWING)
  const top = h - s
  return [
    "M0 0",
    `C-3 ${r(top * 0.35)} 3 ${r(top * 0.7)} 1 ${r(top)}`,
    `C1 ${r(h - s * 0.4)} ${r(w * 0.18)} ${r(h - s * 0.15)} ${r(w * 0.45)} ${r(h - s * 0.35)}`,
    `C${r(w * 0.7)} ${r(h - s * 0.55)} ${r(w)} ${r(h - s * 0.75)} ${r(w)} ${r(h)}`,
    `M${r(w - HEAD_W)} ${r(h - HEAD_H)} L${r(w)} ${r(h)} L${r(w + HEAD_W)} ${r(h - HEAD_H)}`,
  ].join(" ")
}
