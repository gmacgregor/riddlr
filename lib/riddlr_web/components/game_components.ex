defmodule RiddlrWeb.GameComponents do
  @moduledoc """
  Building blocks for the player screens (Home, Lobby, Play).

  These render the `rg-` markup styled by `assets/css/game.css`.
  """
  use Phoenix.Component

  alias RiddlrWeb.GameCopy

  @tones ~w(hi mint sky rose paper red)

  @typedoc "A tile colour. Each one maps to a `data-tone` rule in `game.css`."
  @type tone :: String.t()

  @doc """
  Picks a tone for a name.

  Sums the name's char codes and takes the result mod the number of tones,
  so the same name always gets the same tone. Pass the current user's name
  as `me` to give that player `"hi"`.
  """
  @spec tone(String.t(), String.t() | nil) :: tone()
  def tone(name, me \\ nil)

  def tone(name, name) when is_binary(name), do: "hi"

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
  attr :tone, :string, default: "paper", values: @tones
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
  """
  attr :id, :string, required: true
  attr :seconds, :integer, required: true

  @spec flaps(map()) :: Phoenix.LiveView.Rendered.t()
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
  A time of day in the viewer's own time zone, as `HH:MM`.

  The server cannot know the viewer's zone, so it renders the UTC time and the
  `.LocalTime` hook rewrites it in the browser's locale.
  """
  attr :id, :string, required: true
  attr :at, DateTime, required: true

  @spec local_time(map()) :: Phoenix.LiveView.Rendered.t()
  def local_time(assigns) do
    ~H"""
    <time
      id={@id}
      datetime={DateTime.to_iso8601(@at)}
      phx-hook=".LocalTime"
      phx-update="ignore"
    >{Calendar.strftime(@at, "%H:%M")}</time>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
      export default {
        mounted() {
          const at = new Date(this.el.getAttribute("datetime"))
          this.el.textContent = at.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
        }
      }
    </script>
    """
  end

  @doc """
  A line icon from the game design, drawn in the current text colour.
  Decorative only: it is hidden from screen readers.
  """
  attr :name, :string, required: true, values: ~w(clock trophy check send)

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
        <% "trophy" -> %>
          <path d="M7 4h10v5a5 5 0 0 1-10 0z" /><path d="M7 6H4a3 3 0 0 0 3 4" /><path d="M17 6h3a3 3 0 0 1-3 4" /><path d="M12 14v4" /><path d="M8 21h8" />
        <% "check" -> %>
          <path d="M5 12.5l4.5 4.5L19 7.5" />
        <% "send" -> %>
          <path d="M5 12h14" /><path d="M13 6l6 6-6 6" />
      <% end %>
    </svg>
    """
  end

  @doc """
  The line above a riddle's title: its number as a "No. N" chip, then its
  category. Riddles created before numbering began have no number, so they
  show only the category.
  """
  attr :number, :integer, default: nil
  attr :category, :string, required: true

  @spec kicker(map()) :: Phoenix.LiveView.Rendered.t()
  def kicker(assigns) do
    ~H"""
    <p class="rg-kicker">
      <span :if={@number} class="rg-kicker__num">No. {@number}</span>
      <span>{@category}</span>
    </p>
    """
  end
end
