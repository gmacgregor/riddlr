defmodule RiddlrWeb.GameComponents do
  @moduledoc """
  Building blocks for the player screens (Home, Lobby, Play, Results).

  These render the `rg-` markup styled by `assets/css/game.css`. The clock
  and drop time live in `RiddlrWeb.GameComponents.Clock`, the practice note
  in `RiddlrWeb.GameComponents.Practice`.
  """
  use Phoenix.Component
  use RiddlrWeb, :verified_routes

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
      <span>{if @name, do: "“#{@name}” · #{@category}", else: @category}</span>
    </p>
    """
  end

  @doc """
  A taped note that links to the Standings. A red, white and blue prize
  rosette hangs off each top corner, and a tall gold trophy with confetti
  sits left of the link. Home shows it under the hero and again at the end.
  `id` must be unique on the page.
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil

  @spec standings_note(map()) :: Phoenix.LiveView.Rendered.t()
  def standings_note(assigns) do
    ~H"""
    <div id={@id} class={["rg-standings-note", @class]}>
      <.rosette class="rg-rosette--start" />
      <.rosette class="rg-rosette--end" />
      <.trophy class="rg-standings-note__trophy" />
      <.link navigate={~p"/standings"} class="rg-link-btn">
        {GameCopy.standings_link()}
      </.link>
    </div>
    """
  end

  @doc """
  A puffy prize rosette: a scalloped red ring around a white ring and a
  blue centre with a star, and two notched tails hanging below. It hangs
  off a top corner of the nearest positioned note.
  """
  attr :class, :string,
    required: true,
    doc: ~s(the corner it hangs from: "rg-rosette--start" or "rg-rosette--end")

  @spec rosette(map()) :: Phoenix.LiveView.Rendered.t()
  def rosette(assigns) do
    ~H"""
    <svg class={["rg-rosette", @class]} viewBox="0 0 64 86" aria-hidden="true">
      <path class="rg-rosette__red" d="M25 42 L14 80 L19.5 76 L22.5 83 L33 45 Z" />
      <path class="rg-rosette__blue" d="M39 42 L50 80 L44.5 76.5 L41.5 84 L31 45 Z" />
      <path
        class="rg-rosette__red"
        d="M32.0 9.0 Q40.3 1.8 43.7 11.8 Q54.7 10.4 50.6 21.5 Q60.6 25.9 53.2 33.0 Q59.1 42.4 47.6 43.6 Q47.7 54.5 38.1 50.8 Q32.0 60.1 26.3 49.6 Q16.4 54.2 16.0 43.9 Q5.1 42.3 10.7 33.1 Q2.4 25.7 13.3 21.4 Q10.1 11.0 20.5 12.1 Q23.6 1.5 32.0 9.0 Z"
      />
      <path
        class="rg-rosette__pleat"
        d="M32 9.5 L32 15.5 M45 15 L41.5 19 M51 30 L46 30 M45 45 L41.5 41 M32 51 L32 45 M19 45 L22.5 41 M13 30 L18 30 M19 15 L22.5 19"
      />
      <path
        class="rg-rosette__white"
        d="M32 16 C40 15.5 46.5 22 46 30 C45.5 38.5 40 44.5 32 44 C24 44 17.5 38 18 30 C18.5 22 24 16.5 32 16 Z"
      />
      <path
        class="rg-rosette__blue"
        d="M32 21 C37 20.5 41.5 25 41 30 C41 35.5 37 39 32 39 C26.5 39 23 35 23 30 C23 25 27 21.5 32 21 Z"
      />
      <path
        class="rg-rosette__star"
        d="M32 24 L33.9 27.9 L38 28.4 L35 31.2 L35.8 35.3 L32 33.3 L28.2 35.3 L29 31.2 L26 28.4 L30.1 27.9 Z"
      />
    </svg>
    """
  end

  @doc """
  A pen-drawn trophy: a tall gold cup with a star above it, on a two-step
  plinth marked "1", with confetti thrown around it. `class` places and
  sizes it, e.g. on the Standings note's corner or beside a Standings link.
  """
  attr :class, :any, default: nil

  @spec trophy(map()) :: Phoenix.LiveView.Rendered.t()
  def trophy(assigns) do
    ~H"""
    <svg class={["rg-doodle rg-trophy", @class]} viewBox="0 0 80 92" aria-hidden="true">
      <path class="rg-confetti rg-confetti--red" d="M8 18 L12 23 M71 54 L76 57 M4 62 L7 57" />
      <path class="rg-confetti rg-confetti--blue" d="M68 14 L73 11 M10 40 L5 43 M74 34 L77 39" />
      <path class="rg-confetti rg-confetti--gold" d="M16 6 L16.1 6 M64 26 L64.1 26 M6 50 L6.1 50" />
      <path
        class="rg-trophy__star"
        d="M40 2 L41.7 6 L46 6.4 L42.7 9.2 L43.8 13.5 L40 11.2 L36.2 13.5 L37.3 9.2 L34 6.4 L38.3 6 Z"
      />
      <path d="M28 7 L31 9.5 M52 7 L49 9.5 M30 15 L33 15 M50 15 L47 15" />
      <path d="M23 26 C11 21 8 39 21 45" />
      <path d="M57 26 C69 21 72 39 59 45" />
      <path
        class="rg-trophy__cup"
        d="M22 24 C34 22 46 22 58 24 C57.5 40 51.5 52 40 55 C28.5 52 22.5 40 22 24 Z"
      />
      <path class="rg-trophy__cup" d="M19.5 19 C33 16.5 47 16.5 60.5 19 L58 24 C46 22 34 22 22 24 Z" />
      <path d="M29 29 C29 37 31 43 35 47.5" />
      <path
        class="rg-trophy__cup"
        d="M40 55 C37 57.5 37 61 40 63 C43 61 43 57.5 40 55 Z M40 63 L40 67"
      />
      <path class="rg-trophy__cup" d="M30 67 C37 66 43 66 50 67 L51 74 C44 73 36 73 29 74 Z" />
      <path class="rg-trophy__base" d="M23 74 C34 73 46 73 57 74 L58 86 C46 85 34 85 22 86 Z" />
      <path d="M37.5 78.5 L40.5 76.5 L40.5 83" />
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
