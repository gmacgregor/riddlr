// Results celebrations, ported from the v9 design (celebrate-v9.js).
//
// `celebrate("win")` plays confetti, fireworks or balloons; `celebrate("lose")`
// plays a sad trombone, a poof or a tumbleweed. Each list rotates in order,
// with the position kept in localStorage, so back-to-back riddles don't repeat.
// Everything draws on one fixed, click-through canvas and takes its colours
// and script font from the theme tokens, so light and dark both work. Under
// reduced motion nothing plays.
//
// Returns a function that stops the effect and cleans up its canvas and audio.
// The Results `.Celebrate` hook calls it when the player leaves.

var LISTS = {
  win: ["confetti", "fireworks", "balloons"],
  lose: ["trombone", "poof", "tumbleweed"]
};
var TAU = Math.PI * 2;
var rnd = function (a, b) { return a + Math.random() * (b - a); };
var pick = function (a) { return a[Math.floor(Math.random() * a.length)]; };
var clamp = function (v, lo, hi) { return Math.max(lo, Math.min(hi, v)); };
var reduced = function () { return window.matchMedia("(prefers-reduced-motion: reduce)").matches; };

/* Reads the theme tokens through a hidden probe, once per effect. */
function palette() {
  var probe = document.createElement("i");
  probe.style.cssText = "position:absolute;visibility:hidden;pointer-events:none;font-family:var(--f-display)";
  document.body.appendChild(probe);
  var get = function (name) { probe.style.color = "var(" + name + ")"; return getComputedStyle(probe).color; };
  var pal = {
    ink: get("--fg"), muted: get("--fg-muted"), subtle: get("--fg-subtle"),
    colors: ["--accent", "--success", "--tone-3", "--tone-4", "--tone-7", "--tone-9", "--urgent"].map(get),
    accent: get("--accent"), pale: get("--tone-9"),
    script: getComputedStyle(probe).fontFamily || "cursive",
    dark: document.documentElement.dataset.theme === "dark"
  };
  probe.remove();
  return pal;
}

/* Where the burst starts: the podium, else the board, else mid-screen. Kept inside the viewport. */
function origin(W, H) {
  var el = document.getElementById("podium"), r = el && el.getBoundingClientRect();
  if (!r || !r.height) { el = document.getElementById("panel-board"); r = el && el.getBoundingClientRect(); }
  if (!r || !r.height) return { x: W / 2, y: H * 0.6 };
  return { x: clamp(r.left + r.width / 2, 40, W - 40), y: clamp(r.top + r.height * 0.35, 80, H - 80) };
}

// ───────────── Winner effects ─────────────

function confetti(env) {
  var ps = [], t = 0, fired = 0, at = [0, 0.25, 0.6];
  function burst() {
    for (var i = 0; i < 80; i++) {
      var a = -Math.PI / 2 + rnd(-1, 1) * 1.15, sp = rnd(380, 1000);
      ps.push({
        x: env.o.x + rnd(-30, 30), y: env.o.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
        w: rnd(7, 13), h: rnd(4, 8), rot: rnd(0, TAU), vr: rnd(-9, 9), flip: rnd(0, TAU), vf: rnd(5, 12),
        c: pick(env.pal.colors), round: Math.random() < 0.2, life: rnd(2.6, 4.2), age: 0
      });
    }
  }
  return {
    step: function (dt, ctx) {
      t += dt;
      while (fired < at.length && t >= at[fired]) { burst(); fired++; }
      var drag = Math.exp(-2.2 * dt);
      ps = ps.filter(function (p) { return p.age < p.life && p.y < env.H + 40; });
      ps.forEach(function (p) {
        p.age += dt; p.vx *= drag; p.vy = p.vy * drag + 700 * dt;
        p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vr * dt; p.flip += p.vf * dt;
        ctx.save();
        ctx.globalAlpha = clamp((p.life - p.age) / 0.6, 0, 1);
        ctx.translate(p.x, p.y); ctx.rotate(p.rot); ctx.scale(1, Math.cos(p.flip));
        ctx.fillStyle = p.c;
        if (p.round) { ctx.beginPath(); ctx.arc(0, 0, 4, 0, TAU); ctx.fill(); }
        else ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
        ctx.restore();
      });
      return fired < at.length || ps.length > 0;
    }
  };
}

/* A proper show: a run of single shells in four burst styles, then a finale volley of paired shells. */
function fireworks(env) {
  var rockets = [], sparks = [], flashes = [], t = 0, kinds = ["peony", "ring", "double", "willow", "peony", "ring"];
  var launch = function (delay, kind, big) {
    var c = pick(env.pal.colors), c2 = pick(env.pal.colors);
    rockets.push({
      delay: delay, kind: kind, big: big, x: env.W * rnd(0.08, 0.92), ty: env.H * rnd(0.14, 0.5),
      dur: rnd(0.8, 1.2), age: 0, c: kind === "willow" ? env.pal.accent : c, c2: c2 === c ? env.pal.accent : c2, trail: [], gone: false
    });
  };
  for (var i = 0; i < 12; i++) launch(i * 0.34 + rnd(0, 0.22), kinds[i % kinds.length], false);
  for (var f = 0; f < 6; f++) launch(4.5 + (f >> 1) * 0.35 + rnd(0, 0.15), kinds[(f + 1) % kinds.length], true);
  var spark = function (x, y, a, sp, c, o) {
    sparks.push({
      x: x, y: y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, c: c, age: 0, trail: [],
      life: o.life || rnd(1.3, 1.8), g: o.g === undefined ? 180 : o.g, dr: o.dr || 1.6, tl: o.tl || 6, w: o.w || 2.2
    });
  };
  function explode(r, x, y) {
    var k = r.big ? 1.3 : 1, i, n, a;
    flashes.push({ x: x, y: y, c: r.c, age: 0 });
    if (r.kind === "ring") {
      n = 44;
      for (i = 0; i < n; i++) spark(x, y, (i / n) * TAU, 330 * k, r.c, { dr: 2.6, life: rnd(1.3, 1.6) });
      for (i = 0; i < 14; i++) spark(x, y, rnd(0, TAU), rnd(20, 120) * k, env.pal.accent, { life: rnd(0.8, 1.2) });
    } else if (r.kind === "double") {
      n = 40;
      for (i = 0; i < n; i++) spark(x, y, (i / n) * TAU, 170 * k, r.c2, { dr: 2.2, life: rnd(1.1, 1.4) });
      n = 64;
      for (i = 0; i < n; i++) spark(x, y, (i / n) * TAU + 0.05, 360 * k * rnd(0.95, 1.05), r.c, { life: rnd(1.4, 1.8) });
    } else if (r.kind === "willow") {
      for (i = 0; i < 70; i++) spark(x, y, rnd(0, TAU), rnd(90, 300) * k, r.c, { g: 300, dr: 1.2, life: rnd(2.2, 3.2), tl: 10, w: 1.8 });
    } else {
      n = 76;
      for (i = 0; i < n; i++) {
        a = (i / n) * TAU + rnd(-0.03, 0.03);
        spark(x, y, a, (i % 2 ? 350 : 235) * k * rnd(0.92, 1.06), r.c, {});
      }
      for (i = 0; i < 18; i++) spark(x, y, rnd(0, TAU), rnd(40, 300) * k, env.pal.accent, { life: rnd(0.9, 1.5) });
    }
  }
  return {
    step: function (dt, ctx) {
      t += dt;
      ctx.save();
      if (env.pal.dark) ctx.globalCompositeOperation = "lighter";
      ctx.lineCap = "round";
      rockets.forEach(function (r) {
        if (r.gone || t < r.delay) return;
        r.age += dt;
        var p = Math.min(1, r.age / r.dur), y = env.H - (env.H - r.ty) * (1 - (1 - p) * (1 - p));
        var x = r.x + Math.sin(r.age * 14) * 3;
        r.trail.push([x, y]); if (r.trail.length > 10) r.trail.shift();
        ctx.strokeStyle = r.c; ctx.lineWidth = 3;
        for (var k = 1; k < r.trail.length; k++) {
          ctx.globalAlpha = k / r.trail.length;
          ctx.beginPath(); ctx.moveTo(r.trail[k - 1][0], r.trail[k - 1][1]); ctx.lineTo(r.trail[k][0], r.trail[k][1]); ctx.stroke();
        }
        ctx.globalAlpha = 1; ctx.fillStyle = r.c; ctx.beginPath(); ctx.arc(x, y, 3.5, 0, TAU); ctx.fill();
        if (p >= 1) { r.gone = true; explode(r, x, y); }
      });
      flashes = flashes.filter(function (fl) { return fl.age < 0.35; });
      flashes.forEach(function (fl) {
        fl.age += dt;
        ctx.globalAlpha = clamp(1 - fl.age / 0.35, 0, 1) * 0.7; ctx.strokeStyle = fl.c; ctx.lineWidth = 4;
        ctx.beginPath(); ctx.arc(fl.x, fl.y, 10 + fl.age * 260, 0, TAU); ctx.stroke();
      });
      sparks = sparks.filter(function (s) { return s.age < s.life; });
      sparks.forEach(function (s) {
        var drag = Math.exp(-s.dr * dt);
        s.age += dt; s.vx *= drag; s.vy = s.vy * drag + s.g * dt;
        s.x += s.vx * dt; s.y += s.vy * dt;
        s.trail.push([s.x, s.y]); if (s.trail.length > s.tl) s.trail.shift();
        var fade = clamp((s.life - s.age) / 0.7, 0, 1);
        ctx.strokeStyle = s.c; ctx.lineWidth = s.w;
        for (var k = 1; k < s.trail.length; k++) {
          ctx.globalAlpha = fade * (k / s.trail.length);
          ctx.beginPath(); ctx.moveTo(s.trail[k - 1][0], s.trail[k - 1][1]); ctx.lineTo(s.trail[k][0], s.trail[k][1]); ctx.stroke();
        }
      });
      ctx.restore();
      return rockets.some(function (r) { return !r.gone; }) || sparks.length > 0;
    }
  };
}

function balloons(env) {
  var n = clamp(Math.round(env.W / 55), 14, 30), bs = [];
  for (var i = 0; i < n; i++) {
    var d = Math.random(), r = 22 + d * 40;
    bs.push({
      d: d, r: r, x: rnd(0.04, 0.96) * env.W, y: env.H + r * 2.6 + rnd(0, 260), vy: 110 + d * 190 + rnd(-15, 15),
      amp: 6 + d * 14, f: rnd(0.6, 1.4), ph: rnd(0, TAU), c: pick(env.pal.colors), age: 0
    });
  }
  bs.sort(function (a, b) { return a.d - b.d; });
  return {
    step: function (dt, ctx) {
      bs = bs.filter(function (b) { return b.y > -b.r * 4; });
      bs.forEach(function (b) {
        b.age += dt; b.y -= b.vy * dt;
        var sway = Math.sin(b.age * b.f * 2 + b.ph), x = b.x + sway * b.amp, rx = b.r * 0.82;
        ctx.save();
        ctx.globalAlpha = 0.78 + b.d * 0.22;
        ctx.translate(x, b.y); ctx.rotate(sway * 0.08);
        ctx.strokeStyle = env.pal.ink; ctx.lineWidth = 1 + b.d * 1.5;
        ctx.globalAlpha *= 0.7;
        ctx.beginPath(); ctx.moveTo(0, b.r + 6);
        for (var k = 1; k <= 8; k++) ctx.lineTo(Math.sin(k * 0.9 + b.age * 3) * 3 * b.d + sway * k * 0.6, b.r + 6 + k * b.r * 0.32);
        ctx.stroke();
        ctx.globalAlpha = 0.78 + b.d * 0.22;
        ctx.fillStyle = b.c;
        ctx.beginPath(); ctx.ellipse(0, 0, rx, b.r, 0, 0, TAU); ctx.fill(); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(0, b.r - 1); ctx.lineTo(-5 - b.d * 2, b.r + 8); ctx.lineTo(5 + b.d * 2, b.r + 8); ctx.closePath(); ctx.fill(); ctx.stroke();
        ctx.globalAlpha = 0.45; ctx.fillStyle = "#fff";
        ctx.beginPath(); ctx.ellipse(-rx * 0.42, -b.r * 0.38, rx * 0.16, b.r * 0.28, -0.5, 0, TAU); ctx.fill();
        ctx.restore();
      });
      return bs.length > 0;
    }
  };
}

// ───────────── No-winner effects ─────────────

/* An illustrated trombone plays the classic four-note sad trombone (B♭ A A♭ G) with the slide, the words and a quiet tone. */
var NOTE_AT = [0.45, 1.05, 1.65, 2.25];

function sadHorn() {
  try {
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return function () {};
    var ac = new AC();
    if (ac.state === "suspended") ac.resume().catch(function () {});
    var master = ac.createGain(); master.gain.value = 0.07;
    var lp = ac.createBiquadFilter(); lp.type = "lowpass"; lp.frequency.value = 900; lp.Q.value = 2;
    lp.connect(master); master.connect(ac.destination);
    // each note scoops up into pitch; the last one is held with a slow vibrato and sags flat at the end
    var note = function (at, hz, len, last) {
      var o = ac.createOscillator(), g = ac.createGain(), s = ac.currentTime + at;
      o.type = "sawtooth";
      o.frequency.setValueAtTime(hz * 0.95, s); o.frequency.exponentialRampToValueAtTime(hz, s + 0.07);
      if (last) {
        o.frequency.setValueAtTime(hz, s + len * 0.6); o.frequency.exponentialRampToValueAtTime(hz * 0.94, s + len);
        var lfo = ac.createOscillator(), depth = ac.createGain();
        lfo.frequency.value = 5.5; depth.gain.setValueAtTime(0, s); depth.gain.linearRampToValueAtTime(hz * 0.018, s + 0.6);
        lfo.connect(depth); depth.connect(o.frequency); lfo.start(s + 0.2); lfo.stop(s + len + 0.05);
      }
      g.gain.setValueAtTime(0, s); g.gain.linearRampToValueAtTime(1, s + 0.05);
      g.gain.setValueAtTime(1, s + len * (last ? 0.55 : 0.8)); g.gain.linearRampToValueAtTime(0, s + len);
      o.connect(g); g.connect(lp); o.start(s); o.stop(s + len + 0.05);
    };
    // B♭3, A3, A♭3, G3
    note(NOTE_AT[0], 233.08, 0.5); note(NOTE_AT[1], 220, 0.5); note(NOTE_AT[2], 207.65, 0.5); note(NOTE_AT[3], 196, 2, true);
    var closed = false, close = function () { if (!closed) { closed = true; try { ac.close(); } catch (e) {} } };
    setTimeout(close, 5200);
    return function () { try { master.gain.setTargetAtTime(0, ac.currentTime, 0.05); } catch (e) {} setTimeout(close, 300); };
  } catch (e) { return function () {}; }
}

function trombone(env) {
  var dur = 5.6, t = 0, s = clamp(env.W / 620, 0.55, 1.5), stopHorn = sadHorn();
  var cx = env.W / 2, cy = env.H * 0.42;
  var BRASS = "#cda43a", SHADE = "#a9852a";
  var ease = function (v) { v = clamp(v, 0, 1); return v * v * (3 - 2 * v); };
  // slide travel in px: each lower note pushes the slide further out; the last one wobbles with the vibrato
  var OUT = [34, 68, 102, 150];
  var slide = function (t) {
    var x = 0;
    NOTE_AT.forEach(function (at, i) { x += (OUT[i] - (i ? OUT[i - 1] : 0)) * ease((t - at + 0.06) / 0.16); });
    return x + 5 * Math.sin(t * 5.5 * TAU) * ease((t - NOTE_AT[3] - 0.5) / 0.4) * clamp((NOTE_AT[3] + 2 - t) / 0.4, 0, 1);
  };
  var tube = function (ctx, draw) {
    ctx.lineJoin = "round"; ctx.lineCap = "round";
    ctx.strokeStyle = env.pal.ink; ctx.lineWidth = 11; ctx.beginPath(); draw(); ctx.stroke();
    ctx.strokeStyle = BRASS; ctx.lineWidth = 6.5; ctx.beginPath(); draw(); ctx.stroke();
    ctx.strokeStyle = "rgba(255,255,255,.4)"; ctx.lineWidth = 1.6; ctx.beginPath(); draw(); ctx.stroke();
  };
  function horn(ctx, ext) {
    var xe = 110 + ext;
    tube(ctx, function () { ctx.moveTo(-96, 14); ctx.bezierCurveTo(-142, 14, -142, -34, -96, -34); ctx.lineTo(126, -34); });
    tube(ctx, function () { ctx.moveTo(-96, 14); ctx.lineTo(xe, 14); });
    tube(ctx, function () { ctx.moveTo(-150, 28); ctx.lineTo(xe, 28); });
    tube(ctx, function () { ctx.moveTo(xe, 14); ctx.bezierCurveTo(xe + 22, 14, xe + 22, 28, xe, 28); });
    ctx.strokeStyle = env.pal.ink; ctx.lineWidth = 3;
    [-10, 40].forEach(function (x) { ctx.beginPath(); ctx.moveTo(x, -34); ctx.lineTo(x, 14); ctx.stroke(); });
    ctx.fillStyle = BRASS; ctx.beginPath();
    ctx.moveTo(-160, 22); ctx.lineTo(-150, 22); ctx.lineTo(-150, 34); ctx.lineTo(-160, 34); ctx.quadraticCurveTo(-166, 28, -160, 22); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(120, -41); ctx.quadraticCurveTo(160, -50, 182, -78); ctx.lineTo(182, 10);
    ctx.quadraticCurveTo(160, -18, 120, -27); ctx.closePath(); ctx.fillStyle = BRASS; ctx.fill(); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(150, -40); ctx.quadraticCurveTo(168, -50, 178, -70); ctx.lineTo(178, -40); ctx.closePath(); ctx.fillStyle = SHADE; ctx.fill();
    ctx.beginPath(); ctx.ellipse(182, -34, 9, 44, 0, 0, TAU); ctx.fillStyle = SHADE; ctx.fill(); ctx.strokeStyle = env.pal.ink; ctx.lineWidth = 3; ctx.stroke();
  }
  var measure = function (ctx, txt, size) {
    ctx.font = "700 " + size + "px " + env.pal.script;
    return ctx.measureText(txt).width;
  };
  var pop = function (ctx, txt, x, y, at, tilt, size) {
    var k = ease((t - at) / 0.18);
    if (k <= 0) return;
    ctx.save(); ctx.globalAlpha = k * clamp((dur - t) / 0.6, 0, 1);
    ctx.translate(x, y); ctx.rotate(tilt); ctx.scale(1 + (1 - k) * 0.35, 1 + (1 - k) * 0.35);
    ctx.font = "700 " + size + "px " + env.pal.script; ctx.textAlign = "left"; ctx.fillStyle = env.pal.ink;
    ctx.fillText(txt, 0, 0); ctx.restore();
  };
  return {
    cleanup: stopHorn,
    step: function (dt, ctx) {
      t += dt;
      var a = clamp(t / 0.4, 0, 1) * clamp((dur - t) / 0.6, 0, 1);
      var enter = 1 - Math.pow(1 - clamp(t / 0.6, 0, 1), 3);
      var droop = 0.3 * ease((t - NOTE_AT[3]) / 1.8), bob = Math.sin(t * 2.2) * 2 * s;
      ctx.save();
      ctx.globalAlpha = a;
      ctx.translate(cx - 6 * s - slide(t) * 0.35 * s, cy - (1 - enter) * 120 * s + bob);
      ctx.rotate(droop); ctx.scale(s, s);
      horn(ctx, slide(t));
      ctx.restore();
      var size = Math.round(clamp(env.W / 9, 34, 78)), y = cy + 150 * s + size * 0.2;
      // line 1: "whomp, whomp," line 2: "whoooomp ..." whose o's stretch and dots trail in while the last note is held
      var line1 = "whomp, whomp,", x1 = cx - measure(ctx, line1, size) / 2, w1 = measure(ctx, "whomp, ", size);
      var n = 1 + Math.round(4 * ease((t - NOTE_AT[3]) / 1.5));
      var dots = clamp(Math.floor((t - NOTE_AT[3] - 1.3) / 0.25), 0, 3);
      var line3 = "wh" + new Array(n + 1).join("o") + "mp" + (dots ? " " + new Array(dots + 1).join(".") : "");
      var x3 = cx - measure(ctx, "whoooooomp ...", size) / 2;
      pop(ctx, "whomp,", x1, y, NOTE_AT[0], -0.04, size);
      pop(ctx, "whomp,", x1 + w1, y + 6, NOTE_AT[1], -0.04, size);
      pop(ctx, line3, x3, y + size * 1.05, NOTE_AT[2], -0.03, size);
      return t < dur;
    }
  };
}

function poof(env) {
  var puffs = [], dust = [], t = 0, life = 2;
  for (var i = 0; i < 16; i++) {
    var a = rnd(0, TAU), d = rnd(0, 46);
    puffs.push({ x: env.o.x + Math.cos(a) * d, y: env.o.y + Math.sin(a) * d * 0.7, r: rnd(16, 28), g: rnd(1.8, 2.8), vy: rnd(-26, -10), vx: Math.cos(a) * 14 });
  }
  for (var j = 0; j < 24; j++) {
    var b = rnd(0, TAU), sp = rnd(60, 220);
    dust.push({ x: env.o.x, y: env.o.y, vx: Math.cos(b) * sp, vy: Math.sin(b) * sp, r: rnd(1.4, 3) });
  }
  return {
    step: function (dt, ctx) {
      t += dt;
      var p = clamp(t / life, 0, 1), ease = 1 - Math.pow(1 - Math.min(1, t / 0.9), 3);
      puffs.forEach(function (c) {
        c.x += c.vx * dt * (1 - p); c.y += c.vy * dt;
        var r = c.r * (1 + (c.g - 1) * ease);
        ctx.save();
        ctx.globalAlpha = 0.55 * Math.pow(1 - p, 1.3);
        ctx.fillStyle = env.pal.subtle; ctx.strokeStyle = env.pal.ink; ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.arc(c.x, c.y, r, 0, TAU); ctx.fill();
        ctx.globalAlpha *= 0.5; ctx.stroke();
        ctx.restore();
      });
      dust.forEach(function (d) {
        d.vx *= Math.exp(-2.5 * dt); d.vy *= Math.exp(-2.5 * dt); d.x += d.vx * dt; d.y += d.vy * dt;
        ctx.save(); ctx.globalAlpha = 0.6 * (1 - p); ctx.fillStyle = env.pal.muted;
        ctx.beginPath(); ctx.arc(d.x, d.y, d.r, 0, TAU); ctx.fill(); ctx.restore();
      });
      var ta = clamp((t - 0.25) / 0.3, 0, 1) * clamp((life - t) / 0.5, 0, 1);
      if (ta > 0) {
        ctx.save(); ctx.globalAlpha = ta; ctx.translate(env.o.x, env.o.y - 10 - t * 12); ctx.rotate(-0.07);
        ctx.font = "700 " + Math.round(clamp(env.W / 14, 34, 64)) + "px " + env.pal.script;
        ctx.textAlign = "center"; ctx.fillStyle = env.pal.ink; ctx.fillText("poof.", 0, 0);
        ctx.restore();
      }
      return t < life;
    }
  };
}

function wind(seconds) {
  try {
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return function () {};
    var ac = new AC();
    if (ac.state === "suspended") ac.resume().catch(function () {});
    var len = ac.sampleRate * 2, buf = ac.createBuffer(1, len, ac.sampleRate), d = buf.getChannelData(0), last = 0;
    for (var i = 0; i < len; i++) { last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02; d[i] = last * 3.5; }
    var src = ac.createBufferSource(); src.buffer = buf; src.loop = true;
    var bp = ac.createBiquadFilter(); bp.type = "bandpass"; bp.frequency.value = 500; bp.Q.value = 0.7;
    var g = ac.createGain(); g.gain.value = 0;
    var lfo = ac.createOscillator(); lfo.frequency.value = 0.35;
    var lg = ac.createGain(); lg.gain.value = 220; lfo.connect(lg); lg.connect(bp.frequency);
    src.connect(bp); bp.connect(g); g.connect(ac.destination);
    var now = ac.currentTime;
    g.gain.linearRampToValueAtTime(0.06, now + 1.5);
    g.gain.linearRampToValueAtTime(0.06, now + seconds - 2);
    g.gain.linearRampToValueAtTime(0, now + seconds);
    src.start(); lfo.start();
    var closed = false, close = function () { if (!closed) { closed = true; try { ac.close(); } catch (e) {} } };
    setTimeout(close, seconds * 1000 + 300);
    return function () { try { g.gain.cancelScheduledValues(ac.currentTime); g.gain.setTargetAtTime(0, ac.currentTime, 0.08); } catch (e) {} setTimeout(close, 400); };
  } catch (e) { return function () {}; }
}

function tumbleweed(env) {
  var r = 34 * clamp(env.W / 900, 0.8, 1.2), speed = clamp(env.W / 9, 90, 170);
  var x = -r * 2, t = 0, baseY = env.H - r - 24, arcs = [], gusts = [];
  for (var i = 0; i < 56; i++) {
    var big = i < 10;
    arcs.push({
      cx: big ? rnd(-0.08, 0.08) * r : rnd(-0.4, 0.4) * r, cy: big ? rnd(-0.08, 0.08) * r : rnd(-0.4, 0.4) * r,
      rr: big ? r * rnd(0.85, 1) : r * rnd(0.35, 0.95), a: rnd(0, TAU), len: rnd(1.8, 4.2),
      w: rnd(1.2, 2.2), c: i % 3 ? "#a8844f" : "#8a6a3b"
    });
  }
  var twigs = [];
  for (var m = 0; m < 22; m++) twigs.push({ a: rnd(0, TAU), l0: rnd(0.1, 0.5) * r, l1: rnd(0.8, 1.05) * r, bend: rnd(-0.5, 0.5) });
  for (var j = 0; j < 6; j++) gusts.push({ x: rnd(-200, env.W), y: env.H * rnd(0.45, 0.9), len: rnd(50, 130), v: rnd(260, 420), ph: rnd(0, TAU) });
  var stopWind = wind((env.W + r * 4) / speed + 1);
  return {
    cleanup: stopWind,
    step: function (dt, ctx) {
      t += dt; x += speed * dt;
      var hop = Math.max(0, Math.sin(x * 0.02)) * 10;
      ctx.save();
      ctx.strokeStyle = env.pal.muted; ctx.lineWidth = 1.6; ctx.lineCap = "round"; ctx.globalAlpha = 0.3;
      gusts.forEach(function (g) {
        g.x += g.v * dt; if (g.x - g.len > env.W) g.x = -g.len - rnd(0, 300);
        ctx.beginPath();
        for (var k = 0; k <= 10; k++) {
          var px = g.x - g.len * (k / 10), py = g.y + Math.sin(k * 0.8 + t * 5 + g.ph) * 3;
          if (k) ctx.lineTo(px, py); else ctx.moveTo(px, py);
        }
        ctx.stroke();
      });
      ctx.restore();
      ctx.save();
      ctx.translate(x, baseY - hop); ctx.rotate(x / r);
      ctx.lineCap = "round";
      ctx.fillStyle = "rgba(138,106,59,0.1)";
      ctx.beginPath(); ctx.arc(0, 0, r * 0.92, 0, TAU); ctx.fill();
      arcs.forEach(function (a) {
        ctx.strokeStyle = a.c; ctx.lineWidth = a.w;
        ctx.beginPath(); ctx.arc(a.cx, a.cy, a.rr, a.a, a.a + a.len); ctx.stroke();
      });
      ctx.strokeStyle = "#8a6a3b"; ctx.lineWidth = 1.3;
      twigs.forEach(function (w) {
        var c = Math.cos(w.a), s = Math.sin(w.a);
        ctx.beginPath();
        ctx.moveTo(c * w.l0, s * w.l0);
        ctx.quadraticCurveTo(c * (w.l0 + w.l1) / 2 - s * w.bend * r, s * (w.l0 + w.l1) / 2 + c * w.bend * r, c * w.l1, s * w.l1);
        ctx.stroke();
      });
      ctx.restore();
      return x < env.W + r * 2;
    }
  };
}

var EFFECTS = { confetti: confetti, fireworks: fireworks, balloons: balloons, trombone: trombone, poof: poof, tumbleweed: tumbleweed };

// ───────────── Runner ─────────────

/* The next effect in the list. The position lives in localStorage; without
   it (private mode, blocked storage) the pick is random. */
function nextOf(mode) {
  var list = LISTS[mode], key = "celebrate:" + mode, i = 0;
  try { i = Number(localStorage.getItem(key)) || 0; localStorage.setItem(key, String((i + 1) % list.length)); }
  catch (e) { i = Math.floor(Math.random() * list.length); }
  return list[i % list.length];
}

/* Plays one effect for `mode` ("win" or "lose") and returns its stop function.
   Safe to call stop more than once. */
export function celebrate(mode) {
  if (!LISTS[mode] || reduced()) return function () {};

  var W = window.innerWidth, H = window.innerHeight, dpr = Math.min(window.devicePixelRatio || 1, 2);
  var canvas = document.createElement("canvas");
  canvas.setAttribute("aria-hidden", "true");
  canvas.style.cssText = "position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:1000";
  canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
  document.body.appendChild(canvas);
  var ctx = canvas.getContext("2d");
  var fx = EFFECTS[nextOf(mode)]({ W: W, H: H, o: origin(W, H), pal: palette() });
  var raf = 0, stopped = false, last = performance.now();

  function stop() {
    if (stopped) return;
    stopped = true;
    cancelAnimationFrame(raf);
    if (fx.cleanup) fx.cleanup();
    canvas.remove();
  }

  (function frame(now) {
    if (stopped) return;
    var dt = Math.min(0.05, (now - last) / 1000); last = now;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (fx.step(dt, ctx)) raf = requestAnimationFrame(frame); else stop();
  })(last);

  return stop;
}
