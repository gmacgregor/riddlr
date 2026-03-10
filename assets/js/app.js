// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/riddlr"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// ─── CSS View Transitions for LiveView navigation ────────────────────────────
// Wraps LiveView page loads in document.startViewTransition so that elements
// sharing a view-transition-name morph between pages (e.g. the game timer card).
if (document.startViewTransition) {
  let resolveTransition = null
  let transitionTimeout = null

  window.addEventListener("phx:page-loading-start", ({ detail }) => {
    // Skip form submits — only animate navigations
    if (detail.kind === "submit") return
    clearTimeout(transitionTimeout)
    document.startViewTransition(() => {
      return new Promise(resolve => {
        resolveTransition = resolve
        // Safety valve: resolve after 5s if stop event never fires
        transitionTimeout = setTimeout(() => {
          resolve()
          resolveTransition = null
        }, 5000)
      })
    })
  })

  window.addEventListener("phx:page-loading-stop", () => {
    if (resolveTransition) {
      clearTimeout(transitionTimeout)
      resolveTransition()
      resolveTransition = null
    }
  })
}

// ─── Correct answer: confetti + ring pulse ────────────────────────────────────
function spawnConfetti(cx, cy) {
  const colors = ["#fbbf24", "#34d399", "#60a5fa", "#f472b6", "#a78bfa", "#fb7185", "#4ade80"]
  for (let i = 0; i < 28; i++) {
    const p = document.createElement("div")
    p.className = "confetti-particle"
    const angle = (i / 28) * Math.PI * 2 + (Math.random() - 0.5) * 0.8
    const dist = 70 + Math.random() * 110
    const size = 5 + Math.floor(Math.random() * 7)
    p.style.cssText = `
      left:${cx}px; top:${cy}px;
      width:${size}px; height:${size}px;
      background:${colors[i % colors.length]};
      --vx:${(Math.cos(angle) * dist).toFixed(1)}px;
      --vy:${(Math.sin(angle) * dist - 50).toFixed(1)}px;
      --rot:${Math.round(Math.random() * 720 - 360)}deg;
      animation-delay:${(Math.random() * 0.08).toFixed(3)}s;
    `
    document.body.appendChild(p)
    p.addEventListener("animationend", () => p.remove(), { once: true })
  }
}

window.addEventListener("phx:answer-correct", () => {
  const result = document.getElementById("correct-result")
  if (!result) return

  // Ring pulse animation
  result.style.animation = "none"
  void result.offsetHeight // force reflow
  result.style.animation = "correct-ring-pulse 0.75s ease-out"

  // Confetti burst from center of the result panel
  const r = result.getBoundingClientRect()
  spawnConfetti(r.left + r.width / 2, r.top + r.height / 2)
})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

