defmodule RiddlrWeb.GameComponents do
  @moduledoc """
  Building blocks for the player screens (Home, Lobby, Play, Results).

  These render the `rg-` markup styled by `assets/css/game.css`.
  """
  use Phoenix.Component
  use RiddlrWeb, :verified_routes

  alias Phoenix.LiveView.JS
  alias RiddlrWeb.DropTime
  alias RiddlrWeb.GameCopy

  @tones ~w(variant-1 variant-2 variant-3 variant-4 variant-5 variant-6)

  @typedoc """
  A tile tone, `"variant-1"` to `"variant-6"`. Each one maps to a `data-tone`
  rule in `game.css` that reads `--tone-N`, so the colour mode sets the colours.
  The v9 design names them:

    * `variant-1` - hi, the highlighter (always the viewer's own tile)
    * `variant-2` - mint
    * `variant-3` - sky
    * `variant-4` - rose
    * `variant-5` - paper: the page surface with ink text
    * `variant-6` - red

  Tones 7 to 9 exist in `themes.css` too, but only as page fills (hero,
  timeline markers, practice note). Tiles never use them.
  """
  @type tone :: String.t()

  @doc """
  Picks a tone for a name.

  Sums the name's char codes and takes the result mod the number of tones,
  so the same name always gets the same tone. Pass the current user's name
  as `me` to give that player `"variant-1"`.
  """
  @spec tone(String.t(), String.t() | nil) :: tone()
  def tone(name, me \\ nil)

  def tone(name, name) when is_binary(name), do: "variant-1"

  def tone(name, _me) when is_binary(name) do
    sum = name |> String.to_charlist() |> Enum.sum()
    Enum.at(@tones, rem(sum, length(@tones)))
  end

  @doc """
  The letter shown on a player's tile: the first letter or digit of the name,
  upper-cased, or `"?"` when there is none.
  """
  @spec initial(String.t()) :: String.t()
  def initial(name) when is_binary(name) do
    case Regex.run(~r/[[:alnum:]]/u, name) do
      [char] -> String.upcase(char)
      nil -> "?"
    end
  end

  @doc """
  A letter tile: one character on a coloured square.
  """
  attr :initial, :string, required: true
  attr :tone, :string, default: "variant-5", values: @tones
  attr :size, :string, default: nil, values: [nil, "sm", "lg"]

  @spec tile(map()) :: Phoenix.LiveView.Rendered.t()
  def tile(assigns) do
    ~H"""
    <span
      class={["rg-tile", @size && "rg-tile--#{@size}"]}
      data-tone={@tone}
      aria-hidden="true"
    >{@initial}</span>
    """
  end

  @typedoc "A player in the Lobby's room grid. `me?` marks the viewer."
  @type room_player :: %{id: String.t(), username: String.t(), me?: boolean()}

  @typedoc """
  What the room grid shows: the players with tiles, how many players the
  \"…and N more\" cell counts, and how many empty tiles pad a small room.
  """
  @type room :: %{
          visible: [room_player()],
          more: non_neg_integer(),
          pad: non_neg_integer()
        }

  @room_rows 3
  @room_min 8
  @min_cols 4
  @max_cols 12
  # The "…and N more" cell spans two columns.
  @more_span 2

  @doc """
  Splits a Lobby's players into what the room grid shows.

  The grid holds at most three rows of `cols` cells, with `cols` clamped by
  `clamp_cols/1`, so a full room never puts more than 36 cells in the DOM.
  When the players do not fit, the last two cells become one "…and N more" cell:
  `visible` holds the cells minus two and `more` counts the rest. A room of
  fewer than 8 players gets `pad` empty cells to fill it to 8.
  """
  @spec room_cells([room_player()], integer()) :: room()
  def room_cells(players, cols) when is_list(players) and is_integer(cols) do
    cells = clamp_cols(cols) * @room_rows
    total = length(players)

    if total > cells do
      shown = cells - @more_span
      %{visible: Enum.take(players, shown), more: total - shown, pad: 0}
    else
      %{visible: players, more: 0, pad: max(@room_min - total, 0)}
    end
  end

  @doc """
  Clamps a measured room grid column count to 4..12. The floor matches the
  design; the ceiling bounds the DOM whatever the client sends.
  """
  @spec clamp_cols(integer()) :: pos_integer()
  def clamp_cols(cols) when is_integer(cols), do: cols |> max(@min_cols) |> min(@max_cols)

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
      // Mirrors clock_str/1 in game_components.ex. Change both together.
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

  @doc """
  The "While you wait" note on Home when nothing is scheduled: a practice
  riddle with its answer hidden as blank tiles.

  The answer letters are in the DOM; a practice riddle scores nothing, so
  that is fine. "Peek at the answer" toggles all on the client with `JS`
  commands, which LiveView keeps across patches:

    * `is-open` on the tiles, which CSS reads to show the letters
    * `aria-expanded` on the button, which CSS reads to swap its text
    * `hidden` on the two lines of the polite status, so a screen reader
      hears the answer, or its letter count once hidden again

  `riddle` is any map with a `description` and an `answer`. `n` and `total`
  give its place in the set ("Practice riddle N of M").

  With `on_another` set and more than one riddle in the set, an "Another
  riddle" button closes the answer and pushes that event to the server.
  """
  attr :id, :string, required: true
  attr :riddle, :map, required: true, doc: "a map with `description` and `answer`"
  attr :n, :integer, required: true
  attr :total, :integer, required: true
  attr :on_another, :string, default: nil, doc: "the event \"Another riddle\" pushes"
  attr :rest, :global

  @spec practice_note(map()) :: Phoenix.LiveView.Rendered.t()
  def practice_note(assigns) do
    assigns =
      assign(assigns, :chars, assigns.riddle.answer |> String.upcase() |> String.graphemes())

    ~H"""
    <section id={@id} class="rg-peek" aria-labelledby={"#{@id}-h"} {@rest}>
      <div class="rg-peek__head">
        <h3 id={"#{@id}-h"} class="rg-peek__h">{GameCopy.Home.practice_heading()}</h3>
        <span class="rg-peek__tag">{GameCopy.Home.practice_tag(@n, @total)}</span>
      </div>
      <p class="rg-peek__q">“{@riddle.description}”</p>
      <div id={"#{@id}-answer"} class="rg-peek__a">
        <%= for char <- @chars do %>
          <span :if={char == " "} class="rg-pk-gap" aria-hidden="true"></span>
          <span :if={char != " "} class="rg-pk" aria-hidden="true">
            <span>{char}</span>
          </span>
        <% end %>
      </div>
      <span class="rg-sr-only" role="status">
        <span id={"#{@id}-sr-hidden"}>{GameCopy.Home.practice_status_hidden(@riddle.answer)}</span>
        <span id={"#{@id}-sr-shown"} hidden>{GameCopy.Home.practice_status_shown(@riddle.answer)}</span>
      </span>
      <div class="rg-peek__bar">
        <button
          id={"#{@id}-peek"}
          type="button"
          class="rg-btn rg-peek__btn"
          aria-expanded="false"
          aria-controls={"#{@id}-answer"}
          phx-click={
            JS.toggle_class("is-open", to: "##{@id}-answer")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
            |> JS.toggle_attribute({"hidden", ""}, to: "##{@id}-sr-hidden")
            |> JS.toggle_attribute({"hidden", ""}, to: "##{@id}-sr-shown")
          }
        >
          <span class="rg-peek__show">{GameCopy.Home.practice_peek()}</span>
          <span class="rg-peek__hide">{GameCopy.Home.practice_hide()}</span>
        </button>
        <button
          :if={@on_another && @total > 1}
          type="button"
          class="rg-btn rg-peek__btn rg-peek__next"
          phx-click={close_practice(@id) |> JS.push(@on_another)}
        >
          {GameCopy.Home.practice_another()}
        </button>
        <p :if={GameCopy.Home.practice_note() != ""} class="rg-peek__note">
          {GameCopy.Home.practice_note()}
        </p>
      </div>
    </section>
    """
  end

  # The peek toggle's JS commands stick across patches, so the next riddle
  # would arrive with its answer showing. Close it before asking for one.
  @spec close_practice(String.t()) :: JS.t()
  defp close_practice(id) do
    JS.remove_class("is-open", to: "##{id}-answer")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-peek")
    |> JS.remove_attribute("hidden", to: "##{id}-sr-hidden")
    |> JS.set_attribute({"hidden", ""}, to: "##{id}-sr-shown")
  end

  @doc """
  A line icon from the game design, drawn in the current text colour.
  Decorative only: it is hidden from screen readers.
  """
  attr :name, :string, required: true, values: ~w(clock check send arrow)

  @spec icon(map()) :: Phoenix.LiveView.Rendered.t()
  def icon(assigns) do
    ~H"""
    <svg
      class="rg-icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <%= case @name do %>
        <% "clock" -> %>
          <circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" />
        <% "check" -> %>
          <path d="M5 12.5l4.5 4.5L19 7.5" />
        <% name when name in ["send", "arrow"] -> %>
          <path d="M5 12h14" /><path d="M13 6l6 6-6 6" />
      <% end %>
    </svg>
    """
  end

  @doc """
  The line above a riddle's title: its number as a "No. N" chip, then its
  category. Given a `name`, it reads "No. N", then "name · category", as
  the Home hero does. Riddles created before numbering began have no number,
  so they leave the chip out.
  """
  attr :number, :integer, default: nil
  attr :name, :string, default: nil
  attr :category, :string, required: true

  @spec kicker(map()) :: Phoenix.LiveView.Rendered.t()
  def kicker(assigns) do
    ~H"""
    <p class="rg-kicker">
      <span :if={@number} class="rg-kicker__num">No. {@number}</span>
      <span>{if @name, do: "#{@name} · #{@category}", else: @category}</span>
    </p>
    """
  end

  @doc """
  The status pill in the topbar. Each player page passes its own `kind`:

    * `:play` - a live riddle, "No. N · live" with a dot
    * `:lobby` - "Lobby · No. N"
    * `:results` - "Final · No. N"
    * `:home_live` - "Live now" with a dot, linking to `href` (Play)
    * `:home_next` - "Next MM:SS", counting down to the drop, linking to
      `href` (the Lobby) when given

  The part after the dot is long: CSS hides it on narrow screens. With no
  riddle number, the number part is left out.

  `:home_next` and `:lobby` take the `seconds` until the drop and render it as
  `data-count` for the countdown dot: `future` above 30s, `warn` from 30s and
  `urgent` from 10s. With no `seconds` there is no dot.
  """
  attr :kind, :atom, required: true, values: [:play, :lobby, :results, :home_live, :home_next]
  attr :number, :integer, default: nil
  attr :href, :string, default: nil, doc: "where a Home pill links to"
  attr :id, :string, default: nil, doc: "the `:home_next` clock's id"

  attr :seconds, :integer,
    default: nil,
    doc: "seconds until the drop, for `:home_next` and `:lobby`; sets the countdown dot"

  @spec status_pill(map()) :: Phoenix.LiveView.Rendered.t()
  def status_pill(%{kind: :play} = assigns) do
    ~H"""
    <span class="rg-pill rg-pill--live">
      <span class="rg-live-dot" aria-hidden="true"></span>
      <%= if @number do %>
        No. {@number}<span class="rg-pill__long">&nbsp;· live</span>
      <% else %>
        Live
      <% end %>
    </span>
    """
  end

  def status_pill(%{kind: :home_live} = assigns) do
    ~H"""
    <.link navigate={@href} class="rg-pill rg-pill--live">
      <span class="rg-live-dot" aria-hidden="true"></span>Live now
    </.link>
    """
  end

  def status_pill(%{kind: :home_next, href: nil} = assigns) do
    ~H"""
    <span class="rg-pill rg-pill--soon" data-count={count_level(@seconds)}>
      <.next_clock id={@id} seconds={@seconds || 0} />
    </span>
    """
  end

  def status_pill(%{kind: :home_next} = assigns) do
    ~H"""
    <.link navigate={@href} class="rg-pill rg-pill--soon" data-count={count_level(@seconds)}>
      <.next_clock id={@id} seconds={@seconds || 0} />
    </.link>
    """
  end

  def status_pill(%{kind: kind} = assigns) when kind in [:lobby, :results] do
    ~H"""
    <span
      class={["rg-pill", @kind == :lobby && "rg-pill--soon"]}
      data-count={@kind == :lobby && count_level(@seconds)}
    >
      {if @kind == :lobby, do: "Lobby", else: "Final"}<span
        :if={@number}
        class="rg-pill__long"
      >&nbsp;· No. {@number}</span>
    </span>
    """
  end

  # How near the drop is, for the countdown dot: calm above 30s, amber from
  # 30s, red from 10s.
  @spec count_level(integer() | nil) :: String.t() | nil
  defp count_level(nil), do: nil
  defp count_level(seconds) when seconds > 30, do: "future"
  defp count_level(seconds) when seconds > 10, do: "warn"
  defp count_level(_seconds), do: "urgent"

  # The Home pill's countdown. The server renders the first value. After that
  # the `.PillClock` hook counts down once a second and re-syncs on each
  # `countdown-tick` push, as the `.Flaps` hook does. A scheduled riddle has
  # no server clock, so the hook is what keeps it moving.
  #
  # The topbar slot is a polite live region. `role="timer"` with
  # `aria-live="off"` keeps screen readers from reading every second.
  attr :id, :string, required: true
  attr :seconds, :integer, required: true

  @spec next_clock(map()) :: Phoenix.LiveView.Rendered.t()
  defp next_clock(assigns) do
    ~H"""
    <span class="rg-pill__long">Next&nbsp;</span><span
      id={@id}
      role="timer"
      aria-live="off"
      data-seconds={@seconds}
      phx-hook=".PillClock"
      phx-update="ignore"
    >{clock_str(@seconds)}</span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PillClock">
      // Mirrors clock_str/1 in game_components.ex. Change both together.
      const clockStr = (secs) => {
        secs = Math.max(0, secs)
        const pad = (n) => String(n).padStart(2, "0")
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const s = secs % 60
        return h > 0 ? `${pad(h)}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
      }

      // Counts down to a fixed deadline, not by interval callbacks, so a
      // throttled background tab does not fall behind.
      export default {
        mounted() {
          this.sync(parseInt(this.el.dataset.seconds, 10) || 0)
          this.handleEvent("countdown-tick", ({ seconds }) => this.sync(seconds))
          this.timer = setInterval(() => this.render(), 1000)
        },
        destroyed() {
          clearInterval(this.timer)
        },
        sync(seconds) {
          this.deadline = Date.now() + seconds * 1000
          this.render()
        },
        render() {
          const secs = Math.ceil((this.deadline - Date.now()) / 1000)
          this.el.textContent = clockStr(secs)
        }
      }
    </script>
    """
  end

  @doc """
  A pen-drawn trophy: a gold cup with sparkles. `class` places and sizes it,
  e.g. perched on the Standings note or beside a Standings link.
  """
  attr :class, :any, default: nil

  @spec trophy(map()) :: Phoenix.LiveView.Rendered.t()
  def trophy(assigns) do
    ~H"""
    <svg class={["rg-doodle rg-trophy", @class]} viewBox="0 0 80 84" aria-hidden="true">
      <path
        class="rg-trophy__cup"
        d="M24 14 C34 12.5 46 12.5 56 14 C57 30 52 42 40.5 45 C29 42 23.5 30 24 14 Z"
      />
      <path d="M24.5 19 C15 17.5 13 25 16 30 C18.5 34 23 35 27 35" />
      <path d="M55.5 19 C65 17.5 67 25 64 30 C61.5 34 57 35 53 35" />
      <path d="M40.5 45 L40 55" />
      <path class="rg-trophy__cup" d="M33 55 C38 54 43 54 48 55 L50 62 C43 61 37 61 31 62 Z" />
      <path class="rg-trophy__base" d="M27 62 C36 61 45 61 54 62 L54.5 69 C45 68 36 68 26.5 69 Z" />
      <path d="M33 20 C32.5 27 34 33 37 37" />
      <path d="M8 8 L8 16 M4 12 L12 12" />
      <path d="M70 4 L70 10 M67 7 L73 7" />
      <path d="M72 40 L77 38 M71 46 L77 47 M68 51 L72 55" />
      <path d="M6 44 C4 42 4 40 6 39 M3 50 L8 49" />
    </svg>
    """
  end

  @doc """
  Asks a guest to log in or sign up. A lightning bolt sits each side of the
  links, the two facing apart, each coloured in with a loose yellow fill that
  misses the lines. Shows nothing once signed in.
  """
  attr :current_scope, :map, default: nil
  attr :class, :any, default: nil

  def join_note(assigns) do
    ~H"""
    <p :if={!(@current_scope && @current_scope.user)} id="join-note" class={["rg-join", @class]}>
      <.bolt />
      <span class="rg-join__links">
        <.link navigate={~p"/users/log-in"} class="rg-link-btn">{GameCopy.join_log_in()}</.link>
        {GameCopy.join_or()}
        <.link navigate={~p"/users/register"} class="rg-link-btn">
          {GameCopy.join_sign_up()}
        </.link>
        {GameCopy.join_tail()}
      </span>
      <.bolt flip />
    </p>
    """
  end

  attr :flip, :boolean, default: false

  defp bolt(assigns) do
    ~H"""
    <svg
      class={["rg-doodle rg-doodle--bolt", @flip && "rg-doodle--flip"]}
      viewBox="0 0 48 48"
      aria-hidden="true"
    >
      <path
        class="rg-bolt__fill"
        d="M31 5 C25 12 19 21 13 29 L25 28 C23 34 21 40 18 47 C26 38 33 29 40 20 L28 21 C29 15 30 10 31 5 Z"
      />
      <path
        class="rg-bolt__scribble"
        d="M27 9 L17 25 L29 13 L19 29 L33 19 L23 34 L35 22 L20 42"
      />
      <path d="M29 3 C24 11 17 20 11 28 L23 27 C21 33 19 39 16 46 C24 37 31 28 38 19 L26 20 C27 14 28 8 29 3 Z" />
    </svg>
    """
  end
end
