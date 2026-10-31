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

// ─── View transitions for in-page swaps ──────────────────────────────────────
// The server sends "view-transition" before a patch (push_event with
// dispatch: :before) when the patch should slide, e.g. "Another riddle" on
// Home. The next patch then runs inside document.startViewTransition, but
// only when the browser has it and the player allows motion.
let transitionNext = false
window.addEventListener("phx:view-transition", () => { transitionNext = true })

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)")

function onDocumentPatch(start) {
  const slide = transitionNext && document.startViewTransition && !reduceMotion.matches
  transitionNext = false
  if (slide) document.startViewTransition(start)
  else start()
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // practice_id: the practice riddle Home's static page showed, so the
  // connected mount keeps it instead of picking another.
  params: () => ({
    _csrf_token: csrfToken,
    practice_id: document.getElementById("practice")?.dataset.practiceId,
  }),
  hooks: {...colocatedHooks},
  dom: {onDocumentPatch},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// ─── Colour mode switch ─────────────────────────────────────────────────────
// The topbar button (#theme-switch) flips between light and dark on each
// press. It sets data-theme on <html>, writes the theme cookie so the server
// renders the same mode next time (RiddlrWeb.Theme), and sets the
// theme-color meta so the browser bar matches. No server round trip, so a
// live game keeps its connection, guess field and clock. CSS shows the
// drawing that matches <html data-theme>. The server renders one drawing per
// mode (RiddlrWeb.Theme.themes/0), each with its button label and colour.
function syncThemeSwitch(button) {
  const theme = document.documentElement.dataset.theme
  const icon = button.querySelector(`[data-theme-icon="${theme}"]`)
  if (!icon) return
  button.setAttribute("aria-label", icon.dataset.label)
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta && icon.dataset.color) meta.setAttribute("content", icon.dataset.color)
}

document.addEventListener("click", e => {
  const button = e.target.closest("#theme-switch")
  if (!button) return
  const themes = [...button.querySelectorAll("[data-theme-icon]")].map(el => el.dataset.themeIcon)
  const current = themes.indexOf(document.documentElement.dataset.theme)
  const next = themes[(current + 1) % themes.length]
  document.documentElement.dataset.theme = next
  document.cookie = `theme=${next}; path=/; max-age=31536000; SameSite=Lax`
  syncThemeSwitch(button)
})

// A LiveView mount after live navigation renders the label for the mode it had
// when the page first loaded, so set it again from <html>.
window.addEventListener("phx:page-loading-stop", () => {
  const button = document.getElementById("theme-switch")
  if (button) syncThemeSwitch(button)
})

// ─── CSS View Transitions for LiveView navigation ────────────────────────────
// Wraps LiveView page loads in document.startViewTransition so that elements
// sharing a view-transition-name morph between pages (e.g. the admin header and main).
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

