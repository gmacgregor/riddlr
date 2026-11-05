defmodule RiddlrWeb.DropTime do
  @moduledoc """
  Turns a drop instant into the text players read, in the display time zone
  (`:riddlr, :display_time_zone`, Eastern).

  A drop later today or tomorrow, by the Eastern date, reads "Today at
  1:17pm EST" or "Tomorrow at 1:17pm EST". Any other day gives its date.
  `mid_sentence: true` lowercases the relative word, for text that follows a
  lead such as "Drops".
  """

  defmodule Long do
    @moduledoc """
    The long form in two parts, so a caller can mark the date and time:
    `lead <> marked` is the whole text. `marked` is the short form.
    """
    @enforce_keys [:lead, :marked]
    defstruct [:lead, :marked]

    @type t() :: %__MODULE__{lead: String.t(), marked: String.t()}
  end

  @type opts() :: [mid_sentence: boolean()]

  @doc """
  The short form: `Nov 3, 1:17pm EST`, or `Today at 1:17pm EST`.
  """
  @spec short(DateTime.t(), DateTime.t(), opts()) :: String.t()
  def short(at, now, opts \\ []) do
    long(at, now, opts).marked
  end

  @doc """
  The long form in parts: `Monday, ` and `Nov 3, 1:17pm EST`, or no lead
  and `Today at 1:17pm EST`.
  """
  @spec long(DateTime.t(), DateTime.t(), opts()) :: Long.t()
  def long(at, now, opts \\ []) do
    local = to_display(at)
    time = "#{Calendar.strftime(local, "%-I:%M%P")} #{local.zone_abbr}"

    case Date.diff(DateTime.to_date(local), DateTime.to_date(to_display(now))) do
      0 ->
        %Long{lead: "", marked: relative("Today", opts) <> " at " <> time}

      1 ->
        %Long{lead: "", marked: relative("Tomorrow", opts) <> " at " <> time}

      _ ->
        %Long{
          lead: Calendar.strftime(local, "%A, "),
          marked: Calendar.strftime(local, "%b %-d, ") <> time
        }
    end
  end

  @doc """
  The Eastern date alone, never relative: `Mon, Nov 3`.
  """
  @spec day(DateTime.t()) :: String.t()
  def day(at), do: at |> to_display() |> Calendar.strftime("%a, %b %-d")

  @doc """
  The display time zone, e.g. `America/Toronto`.
  """
  @spec zone() :: String.t()
  defdelegate zone, to: Riddlr.DisplayTime

  @spec relative(String.t(), opts()) :: String.t()
  defp relative(word, opts) do
    if Keyword.get(opts, :mid_sentence, false), do: String.downcase(word), else: word
  end

  @spec to_display(DateTime.t()) :: DateTime.t()
  defp to_display(at), do: DateTime.shift_zone!(at, zone())
end
