defmodule RiddlrWeb.Thinker do
  @moduledoc """
  Hand-drawn people deep in thought, chin on hand, for the corner of Home's
  hero card. There are `count/0` of them, from a teen to two older people,
  and `thinker/1` draws one by number.

  The style follows Shel Silverstein's pen drawings: thin, loose lines, no
  solid fills, lumpy heads, big noses, small eyes looking up, and hair as
  scribbles. Each drawing shares a body (shoulders, neck, hand, thought
  bubbles) and has its own head. Paper parts fill with `--surface-2` to hide
  the lines behind them, so the drawings follow the theme.
  """

  use Phoenix.Component

  @count 9

  @doc "How many thinkers there are. They are numbered 1 to this."
  @spec count() :: pos_integer()
  def count, do: @count

  @doc "A random thinker's number."
  @spec random() :: pos_integer()
  def random, do: Enum.random(1..@count)

  @doc """
  Reads a thinker's number from a string, as sent by the browser. Returns nil
  unless it names one of the thinkers.
  """
  @spec parse(term()) :: pos_integer() | nil
  def parse(param) when is_binary(param) do
    case Integer.parse(param) do
      {n, ""} when n in 1..@count//1 -> n
      _ -> nil
    end
  end

  def parse(_param), do: nil

  @doc """
  Draws thinker `n`. Decorative, so hidden from screen readers.

    1. a teen in a cap worn sideways, with freckles
    2. a twentysomething woman with a ponytail
    3. a twentysomething man with curly hair
    4. a twentysomething woman with an afro and hoop earrings
    5. a twentysomething man in a beanie, with stubble
    6. a thirtysomething woman with a bob and glasses
    7. a thirtysomething man with a side part and a scruffy short beard
    8. an older woman with a bun, half-moon glasses and laugh lines
    9. an older bald man with three hairs, bushy brows, glasses and a long
       white beard
  """
  attr :id, :string, required: true
  attr :n, :integer, required: true, doc: "which thinker, 1 to `count/0`"
  attr :class, :any, default: nil

  @spec thinker(map()) :: Phoenix.LiveView.Rendered.t()
  def thinker(assigns) do
    ~H"""
    <svg
      id={@id}
      class={["rg-thinker", @class]}
      data-thinker={@n}
      viewBox="0 0 100 100"
      aria-hidden="true"
    >
      <path
        class="rg-thinker__paper"
        d="M20 100 C21 90 27 82 38 79 C41 78 44 77 46 76 L54 76 C57 77 60 78 63 79 C73 82 79 90 80 100"
      />
      <path d="M46 63 C46.5 68 46 72 45.5 77 M54 63 C53.5 68 54 72 54.5 77" />
      <path d="M45.5 77 L50 82 L54.5 77 M30 92 C31 95 31.5 97.5 31.5 100 M70 92 C69 95 68.5 97.5 68.5 100" />
      <.head n={@n} />
      <path
        class="rg-thinker__paper"
        d="M43.5 77 C42 85 40 93 38.5 100 L56 100 C55 93 54 85 53 77 Z"
      />
      <path d="M42 85 C46 86.5 50.5 86.5 54.2 85 M41 89 L40.5 92.5 M54.8 89 L55.3 92.5" />
      <path
        class="rg-thinker__paper"
        d="M43 77 C41 72 44 67.5 49 67.5 C52.5 67.5 55 70 54.5 73 C54 76.5 50.5 78.5 47 78.5 C45 78.5 43.5 78 43 77 Z"
      />
      <path d="M46 70.5 C48 69.5 51 70 52 71.5 M45.5 73.5 C47.5 72.5 50.5 73 51.5 74.5" />
      <path d="M49 67.5 C50 65 51 63.5 53 63" />
      <circle class="rg-thinker__paper" cx="71" cy="30" r="1.4" />
      <circle class="rg-thinker__paper" cx="76" cy="23" r="2.2" />
      <path
        class="rg-thinker__paper"
        d="M80 13 C79 8 84 5.5 87 8 C89 4 95 5 95 9.5 C99 10 99 16 95 16.5 C94 20 88 20.5 87 17.5 C83 19.5 79 17 80 13 Z"
      />
    </svg>
    """
  end

  # Small round eyes, pupils up and to the side: thinking.
  attr :x, :any, required: true
  attr :y, :any, required: true

  defp eye(assigns) do
    ~H"""
    <circle class="rg-thinker__paper" cx={@x} cy={@y} r="2.6" />
    <circle class="rg-thinker__ink" cx={@x + 0.9} cy={@y - 1.1} r="1.1" />
    """
  end

  # 1. A teen in a cap worn sideways, with freckles.
  defp head(%{n: 1} = assigns) do
    ~H"""
    <path d="M66 44 C71 42 71.5 50 66 51" />
    <path
      class="rg-thinker__paper"
      d="M36 43 C35 31 43 25 51 25.5 C61 26 67 33 66.5 45 C66 56 59 64.5 50 64.5 C41 64.5 36.5 55 36 43 Z"
    />
    <path
      class="rg-thinker__paper"
      d="M35 38 C35 27 44 21.5 52 22 C61 22.5 67 28.5 67 37 C58 34 44 34 35 38 Z"
    />
    <path d="M35 38 C30 37.5 24 39.5 21 43 C27 43.5 32 41.5 36.5 40.5" />
    <path d="M51 22 C50.5 27 50.5 31 51 35 M42 26 C44 29 45 32 45.5 35 M60 24.5 C59 28 58.5 31 58.5 34.5" />
    <path d="M65 38 L68 42.5 M63 38.5 L64.5 43 M61 38.5 L61.5 42" />
    <.eye x={45} y={45} />
    <.eye x={55.5} y={44.5} />
    <path d="M42 40.5 C43.5 39.5 46 39.5 47.5 40.5 M53 40 C55 39 57.5 39.5 59 40.5" />
    <path d="M50.5 46 C47 51 46 55.5 50 56.5 C53.5 57.5 56 54 53 51.5" />
    <path d="M45.5 60.5 C47.5 59.5 49.5 61 52 60" />
    <g class="rg-thinker__dots">
      <circle cx="41" cy="51" r="0.7" /><circle cx="43.5" cy="52.5" r="0.7" />
      <circle cx="40.5" cy="54" r="0.7" /><circle cx="58" cy="51" r="0.7" />
      <circle cx="60.5" cy="52.5" r="0.7" /><circle cx="58.5" cy="54" r="0.7" />
    </g>
    """
  end

  # 2. A twentysomething woman with a ponytail swinging out.
  defp head(%{n: 2} = assigns) do
    ~H"""
    <path
      class="rg-thinker__paper"
      d="M63 29 C72 23 82 28 85 38 C86 43 85 48 83 52 C81 46 78 41 73 38 C70 36.5 67 36 64.5 36.5 Z"
    />
    <path d="M70 31 C76 33 80 39 82 46 M68 34 C73 36 76 40 78 45" />
    <path
      class="rg-thinker__paper"
      d="M37 44 C36 32 43 25.5 51 25.5 C60 25.5 66 32 65.5 44 C65 56 58.5 64.5 50.5 64.5 C42.5 64.5 37.5 55.5 37 44 Z"
    />
    <path d="M37 43 C35 31 42 22.5 51.5 22.5 C61 22.5 67 30 66 42 C62 35 57 31 51 30.5 C45 31.5 40 36 37 43 Z" />
    <path d="M42 33 C45 28.5 49 26.5 54 26.5 M46 31 C50 28.5 55 28.5 59 30.5 M57 27 C60.5 28.5 63 31.5 64.5 35" />
    <circle class="rg-thinker__paper" cx="64.5" cy="31.5" r="2.4" />
    <.eye x={45.5} y={45} />
    <.eye x={56} y={45} />
    <path d="M42.5 42.5 L41.5 40.5 M44.5 41.5 L44 39.5 M58.5 41.5 L59 39.5 M60.5 42.5 L61.5 40.5" />
    <path d="M51 47 C49.5 50.5 49 53 50.5 54 C52 55 53.5 54.5 54 53.5" />
    <circle cx="50" cy="60" r="1.6" />
    <path d="M38 55 C38.5 57 38 59 37 60.5" />
    """
  end

  # 3. A twentysomething man with a mop of curls.
  defp head(%{n: 3} = assigns) do
    ~H"""
    <path d="M35 45 C30.5 43.5 30 51 35 52 M66 45 C70.5 43.5 71 51 66 52" />
    <path
      class="rg-thinker__paper"
      d="M35 44 C34.5 33 42 27 50.5 27 C59.5 27 66.5 33 66 45 C65.5 57 58.5 65 50.5 65 C42 65 35.5 56 35 44 Z"
    />
    <path
      class="rg-thinker__paper"
      d="M33 40 C29 36 31 29 36 29 C35 23 42 19 46 22.5 C48 17 56 17 57.5 22 C62 19 68.5 23 67 29 C71.5 32 70 39 67 41 C63 36 58 33.5 50.5 33.5 C43 33.5 37 36 33 40 Z"
    />
    <path d="M37 32 c1.5 -2 4 -1 3 1 c-1 2 -3.5 0.5 -2 -1.5 M45 26 c1.5 -2 4 -1 3 1 c-1 2 -3.5 0.5 -2 -1.5 M54 25 c1.5 -2 4 -1 3 1 c-1 2 -3.5 0.5 -2 -1.5 M62 30 c1.5 -2 4 -1 3 1 c-1 2 -3.5 0.5 -2 -1.5 M49 30.5 c1.5 -2 4 -1 3 1 c-1 2 -3.5 0.5 -2 -1.5" />
    <.eye x={45} y={45.5} />
    <.eye x={56} y={45.5} />
    <path d="M41.5 40 C43.5 38.5 46.5 38.5 48 40 M53 39.5 C55 37.5 58.5 38 60 39.5" />
    <path d="M51 47 C46.5 49 45.5 54.5 49 56 C51 57 54 56.5 55.5 55 C57 53 55 51 53 51.5" />
    <path d="M45 60 C48 61.5 52 61.5 55 59.5" />
    """
  end

  # 4. A twentysomething woman with a big afro and hoop earrings.
  defp head(%{n: 4} = assigns) do
    ~H"""
    <path
      class="rg-thinker__paper"
      d="M50 9 C58 5 68 9 70 15 C78 15 84 23 81 31 C87 37 84 47 78 49 C79 55 73 59 68 56 L32 56 C27 59 21 55 22 49 C16 47 13 37 19 31 C16 23 22 15 30 15 C32 9 42 5 50 9 Z"
    />
    <path d="M28 22 c2 -1.5 4 0 2.5 1.5 M40 13 c2 -1.5 4 0 2.5 1.5 M58 12 c2 -1.5 4 0 2.5 1.5 M72 21 c2 -1.5 4 0 2.5 1.5 M24 36 c2 -1.5 4 0 2.5 1.5 M76 36 c2 -1.5 4 0 2.5 1.5 M50 16 c2 -1.5 4 0 2.5 1.5 M66 28 c2 -1.5 4 0 2.5 1.5 M33 29 c2 -1.5 4 0 2.5 1.5 M27 47 c2 -1.5 4 0 2.5 1.5 M72 46 c2 -1.5 4 0 2.5 1.5" />
    <path
      class="rg-thinker__paper"
      d="M37 42 C36.5 32 43 27 51 27 C59 27 65 32 64.5 43 C64 56 58 64.5 50.5 64.5 C43 64.5 37.5 55 37 42 Z"
    />
    <path d="M37.5 36 C42 31.5 47 30 51 30.5 C56 30 61 32 64 36" />
    <circle cx="36.5" cy="56" r="3.2" />
    <circle cx="64.5" cy="56" r="3.2" />
    <.eye x={45.5} y={45} />
    <.eye x={56} y={44.5} />
    <path d="M42.5 40.5 C44 39.5 47 39.5 48.5 40.5 M53 40 C55 38.5 58 39 59.5 40" />
    <path d="M51 46.5 C48 51 47.5 54.5 50.5 55.5 C53 56 55 54.5 54.5 53" />
    <path d="M46.5 59.5 C48.5 61 52 61 54 59.5 C52 59.5 48.5 59.5 46.5 59.5 Z" />
    """
  end

  # 5. A twentysomething man in a beanie, with stubble.
  defp head(%{n: 5} = assigns) do
    ~H"""
    <path d="M35 45 C30.5 43.5 30 51 35 52 M66 45 C70.5 43.5 71 51 66 52" />
    <path
      class="rg-thinker__paper"
      d="M35 42 C35 32 42 27 50.5 27 C59 27 66 32 66 43 C66 56 59 65.5 50.5 65.5 C42 65.5 35 56 35 42 Z"
    />
    <path
      class="rg-thinker__paper"
      d="M34 38 C33 25 41 18 50 18 C60 18 68 25 67 38 Z"
    />
    <path
      class="rg-thinker__paper"
      d="M33 33 C44 31 57 31 68 33 L67.5 39.5 C57 37.5 44 37.5 33.5 39.5 Z"
    />
    <path d="M39 33 L39.5 38.5 M45 32 L45 38 M51 31.8 L51 37.8 M57 32 L57 38 M63 32.5 L62.5 38.5" />
    <path d="M42 21 L43 31 M50 19 L50 31 M58 21 L57 31" />
    <circle class="rg-thinker__paper" cx="50" cy="14.5" r="4" />
    <path d="M47.5 12 L52.5 17 M52.5 12 L47.5 17" />
    <.eye x={45} y={45} />
    <.eye x={56} y={45} />
    <path d="M41.5 41.5 C43.5 40.5 46.5 40.5 48 41.5 M53 41.5 C55 40.5 58 40.5 60 41.5" />
    <path d="M51 46.5 L47.5 54 C49 55.5 52 55.5 54 54.5" />
    <path d="M45.5 60 L54.5 59.5" />
    <g class="rg-thinker__dots">
      <circle cx="39" cy="56" r="0.55" /><circle cx="41" cy="59" r="0.55" />
      <circle cx="43.5" cy="62" r="0.55" /><circle cx="47" cy="63.5" r="0.55" />
      <circle cx="54" cy="63.5" r="0.55" /><circle cx="57.5" cy="62" r="0.55" />
      <circle cx="60" cy="59" r="0.55" /><circle cx="62" cy="56" r="0.55" />
      <circle cx="44" cy="57.5" r="0.55" /><circle cx="57" cy="57.5" r="0.55" />
    </g>
    """
  end

  # 6. A thirtysomething woman with a bob and round glasses.
  defp head(%{n: 6} = assigns) do
    ~H"""
    <path
      class="rg-thinker__paper"
      d="M50 21 C63 21 70 30 70 43 L70.5 58 C67 59.5 64 58.5 63 56 L38 56 C37 58.5 34 59.5 30.5 58 L31 43 C31 30 37 21 50 21 Z"
    />
    <path d="M34 34 L33.5 55 M37 30 L36.5 54 M64 30 L64.5 54 M67 34 L67.5 55" />
    <path
      class="rg-thinker__paper"
      d="M38 42 C37.5 32 43 28 50.5 28 C58 28 63.5 32 63 43 C62.5 56 57.5 64.5 50.5 64.5 C43.5 64.5 38.5 55 38 42 Z"
    />
    <path d="M38 37 C42 33.5 46 34 50 30 C54 34 59 33.5 63 37" />
    <.eye x={45} y={45} />
    <.eye x={56} y={45} />
    <circle cx="45" cy="45" r="4.6" />
    <circle cx="56" cy="45" r="4.6" />
    <path d="M49.6 44.5 C50 43.5 51 43.5 51.4 44.5 M40.4 44 L38 42.5 M60.6 44 L63 42.5" />
    <path d="M51 49 C48.5 52 48.5 54.5 50.5 55 C52.5 55.5 54 54.5 53.5 53.5" />
    <path d="M46.5 59.5 C48.5 58.5 51.5 58.5 54 60" />
    """
  end

  # 7. A thirtysomething man with a side part and a scruffy short beard.
  defp head(%{n: 7} = assigns) do
    ~H"""
    <path d="M35 45 C30.5 43.5 30 51 35 52 M66 45 C70.5 43.5 71 51 66 52" />
    <path
      class="rg-thinker__paper"
      d="M35 43 C34.5 32 42 26.5 50.5 26.5 C59.5 26.5 66.5 32 66 44 C65.5 56 58.5 65 50.5 65 C42 65 35.5 56 35 43 Z"
    />
    <path
      class="rg-thinker__paper"
      d="M34.5 41 C33 30 40 23 50 23 C60 23 67.5 29 66.5 41 C64 35 60 32 55 31.5 C48 31.5 40 34 34.5 41 Z"
    />
    <path d="M43 24.5 C42 28 42 31 43 34 M45.5 26 L52 24 M46 29 L55 26 M47 32 L58 28.5 M50 33.5 L62 30 M41 27 L37.5 30 M40.5 31 L36.5 35" />
    <path
      class="rg-thinker__paper"
      d="M35.5 50 C37 60 43 67 50.5 67 C58 67 64 60 65.5 50 C63 55 60 57 56 56 C53 55 48 55 45 56 C41 57 38 55 35.5 50 Z"
    />
    <path d="M38 53 L39 56 M41 57 L41.5 60 M45 60 L45 63 M56 60 L56 63 M60 57 L59.5 60 M63 53 L62 56 M50.5 61 L50.5 64" />
    <path d="M45.5 56.5 C48 55 53 55 55.5 56.5" />
    <.eye x={45} y={44.5} />
    <.eye x={56} y={44.5} />
    <path d="M41 40 C43 38.5 46.5 38.5 48.5 40 M52.5 39.5 C55 38.5 58.5 38.5 60 40.5" />
    <path d="M50.5 46 C47 49.5 46.5 53 49.5 53.5 C51.5 54 54 53.5 54 52" />
    """
  end

  # 8. An older woman with a bun, half-moon glasses and laugh lines.
  defp head(%{n: 8} = assigns) do
    ~H"""
    <path
      class="rg-thinker__paper"
      d="M44 21 C42 14 47 10 51.5 10.5 C57 11 59 16 57 21 Z"
    />
    <path d="M47 15 C49 12.5 54 13 54.5 16.5 C55 19.5 50 20 49.5 17 C49.5 15.5 51.5 15 52 16.5" />
    <path d="M35 46 C30.5 44.5 30 52 35 53 M66 46 C70.5 44.5 71 52 66 53" />
    <path
      class="rg-thinker__paper"
      d="M35 44 C34.5 31 42 21 50.5 21 C59 21 66.5 31 66 45 C65.5 57 58.5 65 50.5 65 C42 65 35.5 57 35 44 Z"
    />
    <path d="M35.5 40 C37 29 43 22 50.5 22 C58 22 64 29 65.5 40" />
    <path d="M38 34 C42 30 46 31 50.5 26 M63 34 C59 30 55 31 50.5 26 M41 31 C44 27.5 47 26.5 50 24.5 M60 31 C57 27.5 54 26.5 51 24.5" />
    <path d="M43 35.5 C47 34.5 54 34.5 58 35.5" />
    <.eye x={45} y={43.5} />
    <.eye x={56} y={43.5} />
    <path d="M40 48 C41 51.5 48.5 51.5 49.5 48 Z M51.5 48 C52.5 51.5 60 51.5 61 48 Z M49.5 48 C50 47 51 47 51.5 48" />
    <path d="M40.5 39.5 C43 38.5 46.5 38.5 48 39.5 M53 39.5 C55 38.5 58.5 38.5 60.5 39.5" />
    <path d="M61.5 42 L64.5 41 M61.5 44.5 L64.5 45.5 M39.5 42 L36.5 41" />
    <path d="M51 50.5 C48.5 53 48.5 55.5 50.5 56 C52.5 56.5 54 55.5 53.5 54.5" />
    <path d="M45.5 59 C48 61.5 53 61.5 55.5 59" />
    <path d="M42 54.5 C42.5 57 43.5 59 45 60 M59 54.5 C58.5 57 57.5 59 56 60" />
    """
  end

  # 9. An older bald man with three hairs, bushy brows, glasses and a long
  #    white beard.
  defp head(%{n: 9} = assigns) do
    ~H"""
    <path d="M34.5 44 C30 42.5 29.5 50 34.5 51 M66.5 44 C71 42.5 71.5 50 66.5 51" />
    <path
      class="rg-thinker__paper"
      d="M35 42 C34 29 41 21 50.5 21 C60 21 67 29 66 43 C65.5 55 58.5 63 50.5 63 C42 63 35.5 55 35 42 Z"
    />
    <path d="M48 21 C47 17 48.5 14 51 13 M51 21 C51.5 17 54 15 56.5 15.5 M53.5 21.5 C55 19 58 18.5 60 20" />
    <path d="M42 27 C44 25 46.5 24.5 48 25" />
    <path d="M34.5 42 C33.5 37 34.5 34 36.5 32.5 M36.5 43 C35.5 38 36 35.5 38 34 M66.5 42 C67.5 37 66.5 34 64.5 32.5" />
    <path d="M39.5 38 L41 36.5 L42.5 38 L44 36.5 L45.5 38 L47 36.5 L48.5 38 M52.5 38 L54 36.5 L55.5 38 L57 36.5 L58.5 38 L60 36.5 L61.5 38" />
    <.eye x={45} y={43.5} />
    <.eye x={56} y={43.5} />
    <path d="M39.5 40 L50 40 L49.5 47.5 L40 47.5 Z M51 40 L61.5 40 L61 47.5 L51.5 47.5 Z M50 41.5 L51 41.5" />
    <path
      class="rg-thinker__paper"
      d="M36 50 C35 62 39 72 44 79 C46 76 48 79 50.5 81 C53 79 55 76 57 79 C62 72 66 62 65 50 C62 55 58 57 54 55.5 C52 55 49 55 47 55.5 C43 57 39 55 36 50 Z"
    />
    <path d="M41 59 C42 64 43 68 45 72 M46 61 C46.5 66 47.5 70 48.5 74 M55 61 C54.5 66 53.5 70 52.5 74 M60 59 C59 64 58 68 56 72" />
    <path
      class="rg-thinker__paper"
      d="M43 55.5 C46 52 49 53 50.5 54.5 C52 53 55 52 58 55.5 C55 57.5 52.5 57 50.5 56 C48.5 57 46 57.5 43 55.5 Z"
    />
    <path d="M51 45 C48 48.5 48 52 50.5 52.5 C52.5 53 54 52 53.5 51" />
    """
  end
end
