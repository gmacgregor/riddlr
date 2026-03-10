# Lobby & Play Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign lobby and play pages to feel like a tense, social game-show event — dark, electric, physically satisfying on mobile.

**Architecture:** All changes are purely presentational — HEEx templates, CSS, and colocated JS hooks. No Elixir logic changes required. CSS custom properties carry the design tokens so both pages share the same system.

**Tech Stack:** Phoenix LiveView 1.1, Tailwind CSS (via CDN config), custom CSS in `assets/css/app.css`, colocated JS hooks in HEEx templates.

**Spec:** `docs/superpowers/specs/2026-03-10-lobby-play-redesign.md`

---

## Chunk 1: Design Tokens & Global Styles

### Task 1: Add design tokens and global dark-mode base to app.css

**Files:**
- Modify: `assets/css/app.css`

- [ ] **Step 1: Add CSS custom properties and base styles**

Append to `assets/css/app.css` after the existing view transitions block:

```css
/* ─── Design tokens ─────────────────────────────────────────────────────────── */
:root {
  --bg:           #0d0d0f;
  --surface:      #16161a;
  --border:       rgba(255, 255, 255, 0.06);
  --accent:       #7c3aed;
  --accent-glow:  rgba(124, 58, 237, 0.35);
  --text:         #f4f4f5;
  --text-muted:   #71717a;
}

/* ─── Focus ring ─────────────────────────────────────────────────────────────── */
.focus-ring:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px var(--accent), 0 0 0 4px var(--accent-glow);
}

/* ─── Press feel ─────────────────────────────────────────────────────────────── */
.pressable {
  transition: transform 75ms ease;
  cursor: pointer;
}
.pressable:active {
  transform: scale(0.97);
}

/* ─── Reconnection indicator ─────────────────────────────────────────────────── */
@keyframes reconnect-pulse {
  0%, 100% { opacity: 0.4; }
  50%       { opacity: 1; }
}

#reconnect-bar {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 2px;
  background: var(--accent);
  animation: reconnect-pulse 1.2s ease-in-out infinite;
  z-index: 9999;
  display: none;
}

body.phx-loading #reconnect-bar,
body.phx-connecting #reconnect-bar {
  display: block;
}

/* ─── Player dots ────────────────────────────────────────────────────────────── */
@keyframes dot-pulse {
  0%, 100% { opacity: 0.6; transform: scale(1); }
  50%       { opacity: 1;   transform: scale(1.15); }
}

.player-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--accent);
  animation: dot-pulse 2s ease-in-out infinite;
}

/* ─── Countdown tick pulse ───────────────────────────────────────────────────── */
@keyframes countdown-tick {
  0%   { transform: scale(1); }
  30%  { transform: scale(1.03); }
  100% { transform: scale(1); }
}

.countdown-tick {
  animation: countdown-tick 150ms ease-out;
}

/* ─── Lobby timer border glow (intensifies near zero) ────────────────────────── */
.timer-card-urgent {
  box-shadow: 0 0 0 1px var(--accent), 0 0 16px var(--accent-glow);
  transition: box-shadow 0.5s ease;
}

/* ─── Input shake (incorrect answer) ────────────────────────────────────────── */
@keyframes input-shake {
  0%, 100% { transform: translateX(0); }
  20%      { transform: translateX(-6px); }
  40%      { transform: translateX(6px); }
  60%      { transform: translateX(-4px); }
  80%      { transform: translateX(4px); }
}

.shake {
  animation: input-shake 300ms ease-in-out;
}

/* ─── Feed entry slide-in ────────────────────────────────────────────────────── */
@keyframes feed-in {
  from { transform: translateY(-8px); opacity: 0; }
  to   { transform: translateY(0);    opacity: 1; }
}

.feed-entry {
  animation: feed-in 200ms ease-out;
}

/* ─── Riddle reveal (word fade-in handled by JS) ─────────────────────────────── */
.riddle-word {
  opacity: 0;
  transition: opacity 150ms ease;
}
.riddle-word.revealed {
  opacity: 1;
}

/* ─── Cooldown progress bar ──────────────────────────────────────────────────── */
.btn-cooldown {
  position: relative;
  overflow: hidden;
}

.btn-cooldown::after {
  content: "";
  position: absolute;
  left: 0; top: 0; bottom: 0;
  background: rgba(255, 255, 255, 0.15);
  width: var(--cooldown-pct, 100%);
  transition: width 0.1s linear;
}
```

- [ ] **Step 2: Verify no CSS syntax errors**

```bash
mix assets.build 2>&1 | grep -i error
```
Expected: no errors (or no output)

- [ ] **Step 3: Commit**

```bash
git add assets/css/app.css
git commit -m "feat: add design tokens, animations, and utility classes for redesign"
```

---

## Chunk 2: Reconnection Bar & Global App.js

### Task 2: Add reconnection bar element to root layout and global JS hook

**Files:**
- Modify: `lib/riddlr_web/components/layouts/app.html.heex`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Read the app layout file**

```bash
cat lib/riddlr_web/components/layouts/app.html.heex
```

- [ ] **Step 2: Add reconnect bar div to app layout**

Inside `<body>`, before the existing content, add:
```html
<div id="reconnect-bar"></div>
```

- [ ] **Step 3: Verify layout renders in dev**

```bash
mix phx.server
```
Open browser, confirm no visual regression on any page. Stop server.

- [ ] **Step 4: Commit**

```bash
git add lib/riddlr_web/components/layouts/app.html.heex
git commit -m "feat: add reconnection indicator bar to app layout"
```

---

## Chunk 3: Lobby Page Redesign

### Task 3: Redesign lobby.ex template and Countdown hook

**Files:**
- Modify: `lib/riddlr_web/live/game_live/lobby.ex`

This is the full render function replacement. Read the current file first.

- [ ] **Step 1: Read current lobby.ex**

```bash
cat lib/riddlr_web/live/game_live/lobby.ex
```

- [ ] **Step 2: Replace the render function**

Replace the entire `render/1` function (the `~H"""..."""` block and the colocated `<script>`) with:

```elixir
@impl true
def render(assigns) do
  ~H"""
  <div class="min-h-screen flex flex-col items-center justify-center px-4 py-12"
       style="background: var(--bg); color: var(--text)">
    <%!-- Riddle identity --%>
    <div class="text-center mb-8 w-full max-w-sm">
      <div class="flex items-center justify-center gap-2 mb-3">
        <span
          :if={@riddle.category}
          class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
          style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
        >
          <span style="width:6px;height:6px;border-radius:50%;background:var(--accent);display:inline-block"></span>
          {@riddle.category.name}
        </span>
        <span
          :if={@riddle.difficulty}
          class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
          style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
        >
          <span style="width:6px;height:6px;border-radius:50%;background:#d97706;display:inline-block"></span>
          {@riddle.difficulty}
        </span>
      </div>
      <h1 id="riddle-name" class="text-2xl font-bold" style="color: var(--text)">
        {@riddle.name}
      </h1>
    </div>

    <%!-- Timer card --%>
    <div
      id="lobby-timer-card"
      style="view-transition-name: game-timer; background: var(--surface); border: 1px solid var(--surface-border)"
      class="w-full max-w-sm rounded-2xl p-8 text-center mb-6"
    >
      <p class="text-xs font-semibold uppercase tracking-widest mb-4" style="color: var(--text-muted)">
        Starts in
      </p>
      <div
        id="countdown"
        phx-hook=".Countdown"
        data-seconds={@time_remaining}
        class="text-5xl font-mono font-bold tabular-nums"
        style="color: var(--text)"
      >
        {format_time(@time_remaining)}
      </div>
    </div>

    <%!-- Player presence --%>
    <div
      class="w-full max-w-sm rounded-2xl p-6 text-center mb-6"
      style="background: var(--surface); border: 1px solid var(--surface-border)"
    >
      <div id="player-dots" class="flex items-center justify-center gap-2 flex-wrap mb-3">
        <span
          :for={_i <- 1..min(@player_count, 12)//1}
          class="player-dot"
          style={"animation-delay: #{:rand.uniform(20) * 100}ms"}
        />
        <span
          :if={@player_count > 12}
          class="text-xs"
          style="color: var(--text-muted)"
        >
          +{@player_count - 12} more
        </span>
      </div>
      <p class="text-sm" style="color: var(--text-muted)">
        {if @player_count == 1, do: "1 player waiting", else: "#{@player_count} players waiting"}
      </p>
    </div>

    <%!-- Anticipation hint --%>
    <p class="text-sm italic text-center" style="color: #52525b">
      Get ready. The riddle appears when the clock hits zero.
    </p>
  </div>

  <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
    export default {
      mounted() {
        this.tick()
        this.interval = setInterval(() => this.tick(), 1000)
        this.handleEvent("countdown-tick", ({ seconds }) => {
          this.el.dataset.seconds = seconds
          this.tick()
        })
      },
      destroyed() {
        clearInterval(this.interval)
      },
      tick() {
        const secs = parseInt(this.el.dataset.seconds, 10) || 0
        const m = Math.floor(secs / 60).toString().padStart(2, "0")
        const s = (secs % 60).toString().padStart(2, "0")
        this.el.textContent = `${m}:${s}`

        // Color: violet > 60s, white < 60s, red < 10s
        if (secs <= 10) {
          this.el.style.color = "rgb(220,38,38)"
        } else if (secs <= 60) {
          this.el.style.color = "var(--text)"
        } else {
          this.el.style.color = "var(--accent)"
        }

        // Tick pulse: briefly add class, then remove
        this.el.classList.remove("countdown-tick")
        void this.el.offsetWidth // force reflow to restart animation
        this.el.classList.add("countdown-tick")

        // Timer card border glow when urgent
        const card = document.getElementById("lobby-timer-card")
        if (card) {
          if (secs <= 10) {
            card.classList.add("timer-card-urgent")
          } else {
            card.classList.remove("timer-card-urgent")
          }
        }
      }
    }
  </script>
  """
end
```

- [ ] **Step 3: Compile and check for errors**

```bash
mix compile --warnings-as-errors 2>&1
```
Expected: clean compile

- [ ] **Step 4: Run lobby tests**

```bash
mix test test/riddlr_web/live/game_live/lobby_test.exs
```
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/riddlr_web/live/game_live/lobby.ex
git commit -m "feat: redesign lobby page — dark theme, player dots, tick-pulse countdown"
```

---

## Chunk 4: Play Page Redesign

### Task 4: Redesign play.ex template — dark theme, riddle reveal, haptic interactions

**Files:**
- Modify: `lib/riddlr_web/live/game_live/play.ex`

The Elixir logic (mount, handle_event, handle_info, private functions) stays completely unchanged. Only the `render/1` function and the colocated `.SolveTimer` script change.

- [ ] **Step 1: Read the current render function in play.ex**

```bash
grep -n "def render\|<script\|end$" lib/riddlr_web/live/game_live/play.ex | head -30
```

- [ ] **Step 2: Replace the render function**

Replace the entire `render/1` function with the following. The SolveTimer hook logic is unchanged — only presentation changes:

```elixir
@impl true
def render(assigns) do
  ~H"""
  <div
    class="min-h-screen px-4 py-10"
    style="background: var(--bg); color: var(--text)"
  >
    <div class="max-w-lg mx-auto">

      <%!-- Header: badges + riddle name --%>
      <div class="text-center mb-6">
        <div class="flex items-center justify-center gap-2 mb-3">
          <span
            :if={@riddle.category}
            class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
            style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
          >
            <span style="width:6px;height:6px;border-radius:50%;background:var(--accent);display:inline-block"></span>
            {@riddle.category.name}
          </span>
          <span
            :if={@riddle.difficulty}
            class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
            style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
          >
            <span style="width:6px;height:6px;border-radius:50%;background:#d97706;display:inline-block"></span>
            {@riddle.difficulty}
          </span>
          <span
            :if={@game_completed}
            class="inline-flex items-center rounded-full px-3 py-1 text-xs font-medium"
            style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
          >
            Game Over
          </span>
        </div>
        <h1 id="riddle-name" class="text-2xl font-bold" style="color: var(--text)">
          {@riddle.name}
        </h1>

        <%!-- Solve timer --%>
        <div :if={not @game_completed} class="mt-4 flex justify-center">
          <div
            id="solve-timer-card"
            style="view-transition-name: game-timer; background: var(--surface); border: 1px solid var(--surface-border)"
            class="rounded-xl px-6 py-3 text-center"
          >
            <p class="text-[10px] font-semibold uppercase tracking-widest mb-1" style="color: var(--text-muted)">
              Solve time
            </p>
            <div
              id="countdown-timer"
              phx-hook=".SolveTimer"
              data-seconds={@time_remaining}
              class="leading-none"
            >
              <span
                data-timer-display
                class="text-2xl font-mono font-bold tabular-nums"
                style="color: var(--text)"
              >
                {format_time(@time_remaining)}
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Riddle description (word-by-word reveal via JS hook) --%>
      <div
        id="riddle-description"
        class="rounded-2xl p-6 mb-6 text-center"
        style="background: var(--surface); border: 1px solid var(--surface-border)"
        phx-hook=".RiddleReveal"
        data-text={@riddle.description}
      >
        <p class="text-base leading-relaxed" style="color: var(--text)">
          {@riddle.description}
        </p>
      </div>

      <%!-- Correct answer result --%>
      <div
        :if={match?({:correct, _, _}, @submission_state)}
        id="correct-result"
        class="rounded-2xl p-6 mb-6 text-center"
        style="background: rgba(34,197,94,0.08); border: 1px solid rgba(34,197,94,0.25)"
      >
        <p class="text-xl font-bold mb-1" style="color: #4ade80">Correct!</p>
        <p style="color: #86efac">
          {placement_text(elem(@submission_state, 1))} place &mdash; +{elem(@submission_state, 2)} points
        </p>
      </div>

      <%!-- Answer form --%>
      <div :if={not @already_solved and not @game_completed} id="answer-form-container" class="mb-6">
        <form id="answer-form" phx-submit="submit_answer" class="flex flex-col gap-3">
          <input
            id="answer-input"
            type="text"
            name="answer"
            placeholder="Your answer…"
            autocomplete="off"
            class="w-full rounded-xl px-4 py-3 text-base focus-ring pressable"
            style="background: var(--surface); border: 1px solid var(--surface-border); color: var(--text); outline: none"
          />
          <button
            id="submit-btn"
            type="submit"
            class="w-full rounded-xl py-3 text-sm font-semibold pressable focus-ring"
            style="background: var(--accent); color: #fff; min-height: 52px; border: none"
          >
            Submit
          </button>
        </form>

        <div :if={@submission_state == :incorrect} id="incorrect-feedback" class="mt-3">
          <p class="text-sm" style="color: var(--text-muted)">{@try_again_message}</p>
        </div>
        <div :if={match?({:error, _}, @submission_state)} id="error-feedback" class="mt-3">
          <p class="text-sm" style="color: #a78bfa">{elem(@submission_state, 1)}</p>
        </div>
      </div>

      <%!-- Game over (didn't solve) --%>
      <div
        :if={@game_completed and not @already_solved}
        id="game-over"
        class="rounded-2xl p-8 text-center mb-6"
        style="background: var(--surface); border: 1px solid var(--surface-border)"
      >
        <p class="text-lg font-semibold" style="color: var(--text)">Time's up!</p>
        <p class="mt-1" style="color: var(--text-muted)">Better luck next time.</p>
      </div>

      <%!-- Post-game chat --%>
      <div :if={@game_completed} id="chat-form-container" class="mb-6">
        <form id="chat-form" phx-submit="send_chat" class="flex flex-col gap-3">
          <input
            id="chat-input"
            type="text"
            name="message"
            placeholder="Chat with other players…"
            autocomplete="off"
            class="w-full rounded-xl px-4 py-3 text-base focus-ring"
            style="background: var(--surface); border: 1px solid var(--surface-border); color: var(--text); outline: none"
          />
          <button
            type="submit"
            class="w-full rounded-xl py-3 text-sm font-semibold pressable focus-ring"
            style="background: #4338ca; color: #fff; min-height: 52px; border: none"
          >
            Send
          </button>
        </form>
      </div>

      <%!-- Post-game results --%>
      <div :if={@game_completed} id="post-game-results" class="space-y-4">
        <%!-- Winner --%>
        <div
          :if={@riddle.first_solver}
          id="winner-announcement"
          class="rounded-2xl p-6 text-center"
          style="background: rgba(217,119,6,0.08); border: 1px solid rgba(217,119,6,0.25)"
        >
          <p class="text-xs font-semibold uppercase tracking-wide mb-1" style="color: #d97706">Winner</p>
          <p class="text-xl font-bold" style="color: #fcd34d">{@riddle.first_solver.username}</p>
          <p :if={@riddle.first_solve_time} class="text-sm mt-1" style="color: #fbbf24">
            Solved in {format_time(@riddle.first_solve_time)}
          </p>
        </div>

        <%!-- The answer(s) revealed --%>
        <div
          id="correct-answers-revealed"
          class="rounded-2xl p-6"
          style="background: var(--surface); border: 1px solid var(--surface-border)"
        >
          <h3 class="text-xs font-semibold uppercase tracking-wide mb-3" style="color: var(--text-muted)">
            The Answer{if length(@riddle.answers) > 1, do: "s", else: ""}
          </h3>
          <ul class="space-y-1">
            <li :for={answer <- @riddle.answers} class="font-medium" style="color: var(--text)">
              {answer}
            </li>
          </ul>
        </div>

        <%!-- Top solvers leaderboard --%>
        <div
          :if={@top_solvers != []}
          id="game-leaderboard"
          class="rounded-2xl p-6"
          style="background: var(--surface); border: 1px solid var(--surface-border)"
        >
          <h3 class="text-xs font-semibold uppercase tracking-wide mb-3" style="color: var(--text-muted)">
            Top Solvers
          </h3>
          <ol class="space-y-2">
            <li
              :for={solver <- @top_solvers}
              class="flex items-center justify-between py-1"
            >
              <div class="flex items-center gap-3">
                <span class={[
                  "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold",
                  solver.placement == 1 && "bg-amber-500/20 text-amber-400",
                  solver.placement == 2 && "bg-zinc-700 text-zinc-400",
                  solver.placement == 3 && "bg-orange-500/20 text-orange-400",
                  solver.placement > 3 && "bg-zinc-800 text-zinc-500"
                ]}>
                  {solver.placement}
                </span>
                <span class="font-medium" style="color: var(--text)">{solver.username}</span>
              </div>
              <span class="text-sm" style="color: var(--text-muted)">{solver.solve_time_display || "—"}</span>
            </li>
          </ol>
        </div>
      </div>

      <%!-- Answer feed --%>
      <div id="answer-feed" class="mt-8">
        <h2 class="text-xs font-semibold uppercase tracking-wide mb-3" style="color: var(--text-muted)">
          Answer Feed
        </h2>
        <div id="answers" phx-update="stream" class="space-y-0">
          <div
            :for={{dom_id, answer} <- @streams.answers}
            id={dom_id}
            class="feed-entry flex items-center gap-3 px-3 py-2.5 text-sm"
            style={[
              "border-bottom: 1px solid rgba(255,255,255,0.03);",
              cond do
                answer.show_highlight -> "border-left: 3px solid var(--accent); padding-left: 10px"
                Map.get(answer, :chat, false) -> "border-left: 3px solid #4338ca; padding-left: 10px"
                true -> ""
              end
            ]}
          >
            <span class="font-medium shrink-0" style="color: var(--text)">{answer.username}</span>
            <span class="flex-1 truncate" style="color: var(--text-muted)">{answer.text}</span>
            <span :if={answer.offset_ms} class="text-xs shrink-0" style="color: #52525b">
              +{format_offset(answer.offset_ms)}
            </span>
          </div>
        </div>
      </div>

    </div>
  </div>

  <script :type={Phoenix.LiveView.ColocatedHook} name=".SolveTimer">
    export default {
      mounted() {
        this.displayEl = this.el.querySelector("[data-timer-display]")
        this.render(parseInt(this.el.dataset.seconds, 10) || 0)
        this.handleEvent("countdown-tick", ({ seconds }) => {
          this.render(seconds)
        })
      },
      render(secs) {
        const m = Math.floor(secs / 60).toString().padStart(2, "0")
        const s = (secs % 60).toString().padStart(2, "0")
        if (this.displayEl) this.displayEl.textContent = `${m}:${s}`

        const urgency = secs <= 10 ? "critical" : secs <= 30 ? "warning" : "normal"
        const card = this.el.closest("[id='solve-timer-card']") || this.el
        if (card.dataset.urgency !== urgency) {
          card.dataset.urgency = urgency
        }

        if (this.displayEl) {
          if (secs > 30 || secs <= 10) {
            this.displayEl.style.color = ""
          } else {
            const t = (30 - secs) / 20
            const r = Math.round(55 + t * (234 - 55))
            const g = Math.round(65 + t * (88 - 65))
            const b = Math.round(81 + t * (12 - 81))
            this.displayEl.style.color = `rgb(${r},${g},${b})`
          }
        }
      }
    }
  </script>

  <script :type={Phoenix.LiveView.ColocatedHook} name=".RiddleReveal">
    export default {
      mounted() {
        // Only animate on fresh mount (not when game_completed reconnects)
        const para = this.el.querySelector("p")
        if (!para) return

        const words = para.textContent.trim().split(/\s+/)
        para.innerHTML = words
          .map(w => `<span class="riddle-word">${w} </span>`)
          .join("")

        // 300ms initial delay, then 60ms per word
        setTimeout(() => {
          const spans = para.querySelectorAll(".riddle-word")
          spans.forEach((span, i) => {
            setTimeout(() => span.classList.add("revealed"), i * 60)
          })
        }, 300)
      }
    }
  </script>

  <script :type={Phoenix.LiveView.ColocatedHook} name=".AnswerForm">
    export default {
      mounted() {
        this.handleEvent("answer-shake", () => {
          const input = document.getElementById("answer-input")
          if (!input) return
          input.classList.remove("shake")
          void input.offsetWidth
          input.classList.add("shake")
          input.addEventListener("animationend", () => input.classList.remove("shake"), { once: true })
        })

        this.handleEvent("answer-correct", () => {
          const container = document.getElementById("answer-form-container")
          if (container) {
            container.style.transition = "opacity 400ms ease"
            container.style.opacity = "0"
            setTimeout(() => container.style.display = "none", 400)
          }
        })
      }
    }
  </script>
  """
end
```

- [ ] **Step 3: Add `phx-hook=".AnswerForm"` to the answer form container div**

The answer form container `<div>` needs the hook attached so shake/correct events fire:
```heex
<div :if={not @already_solved and not @game_completed}
     id="answer-form-container"
     phx-hook=".AnswerForm"
     class="mb-6">
```
(This is already in the template above — verify it's present after replacing.)

- [ ] **Step 4: Add `push_event("answer-shake", %{})` on incorrect answer in handle_event**

In `handle_event("submit_answer", ...)` in the `else` branch, add the shake event:

```elixir
else
  socket = assign(socket, :try_again_message, try_again())
  {:noreply,
   socket
   |> assign(:submission_state, :incorrect)
   |> push_event("answer-shake", %{})}
end
```

- [ ] **Step 5: Compile with warnings as errors**

```bash
mix compile --warnings-as-errors 2>&1
```
Expected: clean

- [ ] **Step 6: Run play tests**

```bash
mix test test/riddlr_web/live/game_live/play_test.exs
```
Expected: all pass

- [ ] **Step 7: Run full test suite**

```bash
mix test 2>&1 | tail -5
```
Expected: 0 failures

- [ ] **Step 8: Commit**

```bash
git add lib/riddlr_web/live/game_live/play.ex
git commit -m "feat: redesign play page — dark theme, riddle reveal, haptic interactions"
```

---

## Chunk 5: Final Verification

### Task 5: End-to-end smoke test and cleanup

**Files:** none (verification only)

- [ ] **Step 1: Run full test suite one final time**

```bash
mix test
```
Expected: 0 failures

- [ ] **Step 2: Check formatting**

```bash
mix format --check-formatted
```

- [ ] **Step 3: Compile clean**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Manual smoke test checklist**

Start server: `mix phx.server`

Check each item in browser (mobile viewport):
- [ ] Lobby renders with dark background, player dots, tick-pulse countdown
- [ ] Play page renders with dark background, answer form, feed
- [ ] Lobby → Play transition: timer card morphs via view transition
- [ ] Riddle description reveals word-by-word on play page load
- [ ] Incorrect answer: input shakes, try-again message appears in zinc-500
- [ ] Submit button depresses on tap (`pressable` class)
- [ ] Focus ring is violet on input and button
- [ ] Answer feed entries slide in from top
- [ ] Post-game: winner card, answer revealed, leaderboard all styled correctly
- [ ] Reconnect bar: briefly disconnect network, thin violet bar appears at top

- [ ] **Step 5: Final commit if any formatting fixes applied**

```bash
git add -p
git commit -m "chore: formatting and minor cleanup after redesign"
```
