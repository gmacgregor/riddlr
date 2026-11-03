defmodule RiddlrWeb.GameComponents.Clock do
  @moduledoc """
  The time pieces of the player screens: the split-flap countdown and the
  drop time, with its line in the player's own zone.

  These render the `rg-` markup styled by `assets/css/game.css`.
  """
  use Phoenix.Component

  alias RiddlrWeb.DropTime
  alias RiddlrWeb.GameCopy

  @doc """
  Formats seconds as a clock: `MM:SS`, or `HH:MM:SS` from one hour up.
  Negative seconds read as zero. The `.Flaps` hook in `flaps/1` mirrors
  this, so change both together.
  """
  @spec clock_str(integer()) :: String.t()
  def clock_str(seconds) when is_integer(seconds) do
    secs = max(seconds, 0)
    h = div(secs, 3600)
    m = secs |> rem(3600) |> div(60)
    s = rem(secs, 60)

    if h > 0, do: Enum.map_join([h, m, s], ":", &pad/1), else: Enum.map_join([m, s], ":", &pad/1)
  end

  @spec pad(non_neg_integer()) :: String.t()
  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc """
  A split-flap clock counting down to a riddle's start.

  The server renders the first value from `seconds`. After that the `.Flaps`
  hook owns the digits: it counts down once a second, re-syncs on each
  `countdown-tick` push event, and flips only the digits that change. The
  container is `phx-update="ignore"`, so LiveView still patches
  `data-seconds` but leaves the digits to the hook.

  With `blank` set the clock shows `––:––` on empty tiles, labelled as no
  countdown, with no hook and no `seconds`. Home shows it when nothing is
  scheduled.
  """
  attr :id, :string, required: true
  attr :seconds, :integer, default: nil, doc: "seconds to count down; required unless `blank`"
  attr :blank, :boolean, default: false, doc: "a clock with no countdown"

  @spec flaps(map()) :: Phoenix.LiveView.Rendered.t()
  def flaps(%{blank: true} = assigns) do
    ~H"""
    <div id={@id} class="rg-flaps" role="img" aria-label={GameCopy.clock_blank_label()}>
      <%= for char <- String.graphemes("––:––") do %>
        <span
          :if={char == ":"}
          class="rg-flaps__sep"
          aria-hidden="true"
        >:</span><span :if={char != ":"} class="rg-flap rg-flap--empty" aria-hidden="true">{char}</span>
      <% end %>
    </div>
    """
  end

  def flaps(assigns) do
    assigns = assign(assigns, :clock, clock_str(assigns.seconds))

    ~H"""
    <div
      id={@id}
      class={[
        "rg-flaps",
        String.length(@clock) > 5 && "rg-flaps--long",
        urgency(@seconds)
      ]}
      role="timer"
      aria-label={"#{@clock} #{GameCopy.clock_label_tail()}"}
      data-label-tail={GameCopy.clock_label_tail()}
      data-seconds={@seconds}
      phx-hook=".Flaps"
      phx-update="ignore"
    >
      <%= for char <- String.graphemes(@clock) do %>
        <span
          :if={char == ":"}
          class="rg-flaps__sep"
          aria-hidden="true"
        >:</span><span :if={char != ":"} class="rg-flap" aria-hidden="true">{char}</span>
      <% end %>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Flaps">
      // Mirrors clock_str/1 above. Change both together.
      const clockStr = (secs) => {
        secs = Math.max(0, secs)
        const pad = (n) => String(n).padStart(2, "0")
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const s = secs % 60
        return h > 0 ? `${pad(h)}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
      }

      export default {
        mounted() {
          this.seconds = parseInt(this.el.dataset.seconds, 10) || 0
          this.handleEvent("countdown-tick", ({ seconds }) => {
            this.seconds = seconds
            this.start()
            this.render()
          })
          this.start()
          this.render()
        },
        destroyed() {
          clearInterval(this.timer)
        },
        // Restart the local second so it lines up with the server's tick.
        start() {
          clearInterval(this.timer)
          this.timer = setInterval(() => {
            this.seconds = Math.max(0, this.seconds - 1)
            this.render()
          }, 1000)
        },
        render() {
          const str = clockStr(this.seconds)
          const chars = [...str]
          const layout = chars.map((c) => (c === ":" ? ":" : "d")).join("")
          const el = this.el

          // Rebuild the cells only when the shape changes (MM:SS <-> HH:MM:SS).
          // Read the shape from the DOM: LiveView strips data-* attributes it
          // did not render, so the hook cannot keep it on the element.
          const current = [...el.children]
            .map((n) => (n.classList.contains("rg-flaps__sep") ? ":" : "d"))
            .join("")
          if (current !== layout) {
            el.innerHTML = chars
              .map((c) => c === ":"
                ? '<span class="rg-flaps__sep" aria-hidden="true">:</span>'
                : '<span class="rg-flap" aria-hidden="true"></span>')
              .join("")
          }
          el.classList.toggle("rg-flaps--long", chars.length > 5)

          chars.forEach((c, i) => {
            const node = el.children[i]
            if (c === ":" || node.textContent === c) return
            node.textContent = c
            node.classList.remove("is-tick")
            // Force a reflow so the browser restarts the flip animation.
            void node.offsetWidth
            node.classList.add("is-tick")
          })

          // Mirrors urgency/1.
          el.classList.toggle("is-crit", this.seconds <= 5)
          el.classList.toggle("is-warn", this.seconds > 5 && this.seconds <= 10)
          el.setAttribute("aria-label", `${str} ${el.dataset.labelTail}`)
        }
      }
    </script>
    """
  end

  # The clock's warning class. The `.Flaps` hook mirrors these thresholds.
  @spec urgency(integer()) :: String.t() | nil
  defp urgency(seconds) when seconds <= 5, do: "is-crit"
  defp urgency(seconds) when seconds <= 10, do: "is-warn"
  defp urgency(_seconds), do: nil

  @doc """
  A drop date and time in the display zone (Eastern), e.g. `Nov 3, 1:17pm EST`
  or `Today at 1:17pm EST`. See `RiddlrWeb.DropTime`.
  """
  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :now, DateTime, doc: "what today is judged from; defaults to the clock"
  attr :format, :string, default: "short", values: ~w(short long)
  attr :local, :boolean, default: true, doc: "add the `drop_local/1` line after the time"

  attr :mid_sentence, :boolean,
    default: false,
    doc: "lowercase Today and Tomorrow, for a time that follows a lead such as \"Drops\""

  @spec drop_time(map()) :: Phoenix.LiveView.Rendered.t()
  def drop_time(assigns) do
    assigns =
      assigns
      |> assign_new(:now, fn -> Riddlr.Clock.utc_now() end)
      |> then(fn %{at: at, now: now} = assigns ->
        opts = [mid_sentence: assigns.mid_sentence]

        assign(assigns,
          iso: DateTime.to_iso8601(at),
          short: DropTime.short(at, now, opts),
          long: DropTime.long(at, now, opts)
        )
      end)

    ~H"""
    <%!-- No whitespace between the parts: it would show as a space before the comma. --%>
    <time :if={@format == "short"} id={@id} datetime={@iso}>{@short}</time>
    <time :if={@format == "long"} id={@id} datetime={@iso}>{@long.lead}<span class="rg-underlined">{@long.marked}</span></time><.drop_local
      :if={@local}
      id={"#{@id}-local"}
      at={@at}
    />
    """
  end

  @doc """
  The line under a drop time that gives it in the player's own zone, e.g.
  "Your time: Today at 10:17am PST".

  It starts hidden. The `.LocalDrop` hook shows it only when the browser's
  zone has a different UTC offset from the display zone at the drop instant,
  so Eastern players never see it. `drop_time/1` adds it by default; place it
  yourself, with `local={false}` there, when the time sits mid-sentence.
  """
  attr :id, :string, required: true
  attr :at, DateTime, required: true

  @spec drop_local(map()) :: Phoenix.LiveView.Rendered.t()
  def drop_local(assigns) do
    ~H"""
    <span
      id={@id}
      class="rg-drop-local"
      data-at={DateTime.to_iso8601(@at)}
      data-zone={DropTime.zone()}
      phx-hook=".LocalDrop"
      phx-update="ignore"
      hidden
    >
      {GameCopy.Home.drop_local_lead()} <span data-local-text></span>
    </span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalDrop">
      import {localDropText} from "@/js/drop_time"

      export default {
        mounted() {
          const browserZone = Intl.DateTimeFormat().resolvedOptions().timeZone
          const text = localDropText(this.el.dataset.at, browserZone, this.el.dataset.zone)
          if (!text) return
          this.el.querySelector("[data-local-text]").textContent = text
          this.el.hidden = false
        }
      }
    </script>
    """
  end
end
