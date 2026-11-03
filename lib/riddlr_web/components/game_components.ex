defmodule RiddlrWeb.GameComponents do
  @moduledoc """
  Building blocks for the player screens (Home, Lobby, Play, Results).

  These render the `rg-` markup styled by `assets/css/game.css`. The clock
  and drop time live in `RiddlrWeb.GameComponents.Clock`, the practice note
  in `RiddlrWeb.GameComponents.Practice`.
  """
  use Phoenix.Component
  use RiddlrWeb, :verified_routes

  alias RiddlrWeb.GameComponents.Clock
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
    >{Clock.clock_str(@seconds)}</span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PillClock">
      // Mirrors clock_str/1 in game_components/clock.ex. Change both together.
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
