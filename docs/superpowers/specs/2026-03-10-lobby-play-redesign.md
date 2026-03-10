# Lobby & Play Page Redesign — Design Spec

**Date:** 2026-03-10
**Status:** Approved

## Goal

Redesign the lobby and play pages to feel like a tense, social game show event — dark, electric,
physically satisfying to use on mobile. Fun but understated; sleek and haptic.

## Visual Language

### Palette

| Token | Value | Use |
|-------|-------|-----|
| Background | `#0d0d0f` | Page background |
| Surface | `#16161a` | Cards, panels |
| Border | `rgba(255,255,255,0.06)` | Hairline dividers |
| Accent | `#7c3aed` | Timer, CTAs, focus rings, correct answers |
| Accent glow | `rgba(124,58,237,0.35)` | Box-shadow bloom |
| Text primary | `#f4f4f5` | Headings, body |
| Text muted | `zinc-500 (#71717a)` | Labels, hints |

No background gradients. Depth from border opacity and shadow only. One exception: CTA button gets a radial glow on hover/focus.

### Typography

- Headings: system-ui, heavy weight
- Timer: monospace stack, `font-variant-numeric: tabular-nums`
- Body: regular weight, zinc-100
- Minimum text size: 16px
- Minimum hit target: 48px

## Lobby Page

### Layout

- Single centered column, max-width 480px (down from 672px)
- Vertical order: riddle name → player presence → countdown → hint text

### Riddle Name & Badges

- Restrained heading size — prominent but not oversized
- Badges reworked: dark pill with colored dot (`● Science`) instead of colored background
- Dot color: violet for category, amber for difficulty

### Player Presence

- Replace plain number with cluster of glowing dots (one per player, max 12 shown, then `+N more`)
- Each dot: 10px circle, violet, staggered pulse animation (`opacity 0.6→1.0`)
- Below dots: `"12 players waiting"` in zinc-500

### Countdown

- Restrained size — prominent mono digits, not full-viewport
- Violet when >60s → white when <60s → red when <10s (color transition, not jump)
- Per-tick scale pulse: `scale(1.0) → scale(1.03) → scale(1.0)`, 150ms — number thumps
- Timer card border glow intensifies as time approaches zero

### Hint Text

- Single italic line in zinc-600: *"Get ready. The riddle appears when the clock hits zero."*

## Play Page

### Riddle Reveal

- On transition from lobby: riddle description starts `opacity: 0; filter: blur(4px)`
- After 300ms delay: words fade in one at a time, 60ms per word
- Feels deliberate without being slow

### Answer Input

- Full-width, dark surface (`#16161a`)
- Violet focus ring: `box-shadow: 0 0 0 2px #7c3aed, 0 0 0 4px rgba(124,58,237,0.25)`
- On focus: `translateY(-1px)` lift + shadow bloom
- Submit button: full-width on mobile, 52px tall, 12px radius, violet background

### Feedback States

- **Incorrect:** input shakes horizontally (3 oscillations, 300ms), message in zinc-400 — no red alarm
- **Correct:** existing confetti kept; input/button fade out, success state slides up
- **Cooldown:** submit button shows draining progress bar across its face instead of disabled state

### Answer Feed

- Slim rows, no card borders — `1px rgba(255,255,255,0.03)` separator lines
- New entries slide in from top: `translateY(-8px)→0, opacity 0→1`, 200ms
- Correct answers: 3px violet left border
- Chat messages: indigo tint
- Nothing boxy

### Timer

Keep existing SolveTimer hook with heartbeat and urgency states — already good.

## Global Interactions

### Press Feel

All buttons and interactive surfaces:
```css
active:scale-[0.97] transition-transform duration-75
```
Everything that can be pressed, depresses.

### Focus States

Consistent across all interactive elements:
```css
outline: none;
box-shadow: 0 0 0 2px #7c3aed, 0 0 0 4px rgba(124,58,237,0.25);
```

### Reconnection Indicator

While LiveView is reconnecting: 2px violet line pulses across top of viewport (`position: fixed; top: 0`). Thin, unobtrusive.

## What We're NOT Doing

- No dark/light toggle
- No custom scrollbars
- No parallax
- No skeleton loaders
- No modal overlays
- No custom font loading
