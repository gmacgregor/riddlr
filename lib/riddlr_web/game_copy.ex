defmodule RiddlrWeb.GameCopy do
  @moduledoc """
  The words the player screens show.

  Templates, components and tests read copy from here, so a wording change
  happens in one place and the tests follow it.
  """

  # ─── Lobby ────────────────────────────────────────────────────────────────────

  @doc "The flash shown when a player opens a lobby that is not open."
  @spec lobby_unavailable() :: String.t()
  def lobby_unavailable, do: "Game lobby is not yet available."

  @doc "The Lobby's heading, above the clock."
  @spec lobby_heading() :: String.t()
  def lobby_heading, do: "The riddle drops in"

  @doc "The words before the drop time in the Lobby's when line."
  @spec lobby_when_lead() :: String.t()
  def lobby_when_lead, do: "Drops for everyone at"

  @doc "The words after the drop time in the Lobby's when line."
  @spec lobby_when_tail() :: String.t()
  def lobby_when_tail, do: "Stay on this screen — it opens by itself."

  @doc "The fact that gives a riddle's solve time, already formatted as a clock."
  @spec solve_time(String.t()) :: String.t()
  def solve_time(clock), do: "#{clock} to solve"

  @doc "The fact that says which places earn points."
  @spec scoring_rule() :: String.t()
  def scoring_rule, do: "Top 10 score"

  @doc "The Lobby's call to get ready, shown in the last seconds."
  @spec lobby_ready() :: String.t()
  def lobby_ready, do: "Fingers on the keys"

  # ─── Lobby room ─────────────────────────────────────────────────────────────────

  @doc "The heading of the Lobby's room panel."
  @spec room_heading() :: String.t()
  def room_heading, do: "In the room"

  @doc "How many players are in the Lobby, e.g. \"1,204 here\"."
  @spec room_count(non_neg_integer()) :: String.t()
  def room_count(count), do: "#{delimit(count)} here"

  @doc "The name under the viewer's own tile."
  @spec room_you() :: String.t()
  def room_you, do: "you"

  @doc "The room grid's last cell when not every player fits, e.g. \"…and 40 more\"."
  @spec room_more(pos_integer()) :: String.t()
  def room_more(count), do: "…and #{delimit(count)} more"

  @doc """
  The words after the first name in the join ticker, given how many others
  joined with them, e.g. " and 2 others just joined".
  """
  @spec ticker_tail(non_neg_integer()) :: String.t()
  def ticker_tail(0), do: " just joined"
  def ticker_tail(1), do: " and 1 other just joined"

  def ticker_tail(others),
    do: " and #{delimit(others)} others just joined"

  @doc "The heading of the Lobby's rules panel."
  @spec rules_heading() :: String.t()
  def rules_heading, do: "How it works"

  @doc """
  The game's rules, as the Lobby lists them. Each line must match the real
  rules: the 1s cooldown and the points table in `Riddlr.Gameplay`, and the
  exact (trimmed, case-blind) answer match.
  """
  @spec rules() :: [String.t()]
  def rules do
    [
      "The riddle appears for everyone at the same second.",
      "Guess as often as you like — one guess per second.",
      "The ten fastest correct answers score, from 10 points down to 1. Spelling counts."
    ]
  end

  # ─── Clock ────────────────────────────────────────────────────────────────────

  @doc """
  The words after the time in the split-flap clock's screen-reader label,
  e.g. "02:05 until the riddle starts".
  """
  @spec clock_label_tail() :: String.t()
  def clock_label_tail, do: "until the riddle starts"

  # ─── Play ─────────────────────────────────────────────────────────────────────

  @doc """
  A place as an ordinal, e.g. 1 as "1st", 12 as "12th" and 22 as "22nd".
  """
  @spec ordinal(pos_integer()) :: String.t()
  def ordinal(n) when is_integer(n) and n > 0 do
    suffix =
      case {rem(n, 100), rem(n, 10)} do
        {teen, _} when teen in 11..13 -> "th"
        {_, 1} -> "st"
        {_, 2} -> "nd"
        {_, 3} -> "rd"
        _ -> "th"
      end

    "#{n}#{suffix}"
  end

  @doc """
  Seconds as `M:SS`, e.g. 270 as "4:30". Negative seconds read as zero.
  """
  @spec m_ss(integer()) :: String.t()
  def m_ss(seconds) when is_integer(seconds) do
    secs = max(seconds, 0)
    "#{div(secs, 60)}:#{secs |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc "How many guesses the Play feed holds, e.g. \"12 guesses\"."
  @spec guess_count(non_neg_integer()) :: String.t()
  def guess_count(1), do: "1 guess"
  def guess_count(count), do: "#{delimit(count)} guesses"

  @doc "How many players have solved the riddle, e.g. \"3 solved\"."
  @spec solved_count(non_neg_integer()) :: String.t()
  def solved_count(count), do: "#{delimit(count)} solved"

  @doc "The Play feed's line when nobody has guessed yet."
  @spec feed_empty() :: String.t()
  def feed_empty, do: "No guesses yet. Be the first to swing."

  @doc "The stamp on a solve in the Play feed, e.g. \"Solved · 2nd\"."
  @spec feed_solved(pos_integer()) :: String.t()
  def feed_solved(placement), do: "Solved · #{ordinal(placement)}"

  @doc "The divider on Results between the riddle's guesses and the chat."
  @spec chat_divider() :: String.t()
  def chat_divider, do: "Riddle ended"

  @doc """
  The Results chat on an archived riddle. Archive drops the guesses and
  closes chat, so the list is empty.
  """
  @spec chat_archived() :: String.t()
  def chat_archived, do: "Chat closed. This riddle's guesses and messages are gone."

  @doc "The placeholder in the Results chat field."
  @spec chat_placeholder() :: String.t()
  def chat_placeholder, do: "Say something nice to the winner"

  @doc "The message when a player sends an empty guess."
  @spec guess_empty() :: String.t()
  def guess_empty, do: "Type an answer first."

  @doc "The message when a player guesses inside the 1s cooldown."
  @spec guess_cooldown() :: String.t()
  def guess_cooldown, do: "One guess per second. Breathe."

  @quips [
    "Not quite. Read it again.",
    "Nope. The riddle is smirking at you.",
    "Cold. Very cold.",
    "That's a no. Shake it off.",
    "Wrong, but bold. Try again.",
    "So close? Hard to say. Still no.",
    "Uuuh… no! Think harder.",
    "Ooopsie whoopise, not quite. Go on, guess again!",
    "Good guess, but no! So close… or not.",
    "Nooooope! Wrack that brain.",
    "Not so, unfortunately. Back to the drawing board!"
  ]

  @doc "Every line a wrong guess can get."
  @spec quips() :: [String.t()]
  def quips, do: @quips

  @doc """
  A random line for a wrong guess, never the same as `last`. A new line
  each time makes the status region speak again.
  """
  @spec quip(String.t() | nil) :: String.t()
  def quip(last \\ nil), do: Enum.random(@quips -- [last])

  @doc "The solved panel's title, given the player's place and points."
  @spec solved_title(pos_integer(), non_neg_integer()) :: String.t()
  def solved_title(1, _points), do: "First! Nobody was faster."
  def solved_title(_placement, 0), do: "Cracked it — just off the board."
  def solved_title(placement, _points), do: "Cracked it. #{ordinal(placement)} place."

  @doc """
  The solved panel's line under the title, given the points and the seconds
  left in the round.
  """
  @spec solved_sub(non_neg_integer(), integer()) :: String.t()
  def solved_sub(points, seconds_left),
    do: "+#{points} pts · round closes in #{m_ss(seconds_left)}. Watch the others sweat."

  # ─── Results ────────────────────────────────────────────────────────────────────────────

  @doc """
  A solve time in seconds with one decimal, e.g. 3456 ms as "3.5s". A solve
  with no time (the riddle had no live date) reads "—".
  """
  @spec solve_secs(non_neg_integer() | nil) :: String.t()
  def solve_secs(nil), do: "—"

  def solve_secs(ms) when is_integer(ms),
    do: :erlang.float_to_binary(ms / 1000, decimals: 1) <> "s"

  @doc "The words before the first solver's name on Results."
  @spec results_by_lead() :: String.t()
  def results_by_lead, do: "Cracked first by"

  @doc "The Results line when nobody solved the riddle."
  @spec results_unsolved() :: String.t()
  def results_unsolved, do: "Nobody cracked it before the clock ran out."

  @doc "The name under an empty podium slot."
  @spec podium_open() :: String.t()
  def podium_open, do: "Open"

  @doc "The Results board's line when nobody solved the riddle."
  @spec board_empty() :: String.t()
  def board_empty, do: "The board is empty. The riddle wins this round."

  @doc "The heading of the Results points payout."
  @spec payout_heading() :: String.t()
  def payout_heading, do: "Points this riddle"

  @doc "The name in a payout cell nobody claimed."
  @spec payout_unclaimed() :: String.t()
  def payout_unclaimed, do: "unclaimed"

  @typedoc """
  The viewer's own result on Results. `none?` marks a stamp that earned no
  points, which the design draws dark and flat.
  """
  @type you_card :: %{stamp: String.t(), none?: boolean(), title: String.t(), sub: String.t()}

  @doc """
  The viewer's card on Results, given their solve (or `nil`) and whether they
  joined the riddle by guessing while it was live.
  """
  @spec you_card(%{placement: pos_integer(), points: non_neg_integer()} | nil, boolean()) ::
          you_card()
  def you_card(nil, false) do
    %{
      stamp: "—",
      none?: true,
      title: "You weren't in this one",
      sub: "Join the next lobby to get on the board."
    }
  end

  def you_card(nil, true) do
    %{
      stamp: "0",
      none?: true,
      title: "Not this time",
      sub: "No points, but you know it now. Next one's yours."
    }
  end

  def you_card(%{placement: placement, points: points}, _joined?) do
    %{
      stamp: placement |> ordinal() |> String.upcase(),
      none?: points == 0,
      title: if(placement == 1, do: "You won it", else: "You placed #{ordinal(placement)}"),
      sub:
        if(points > 0,
          do: "+#{points} pts for this riddle",
          else: "Solved, but outside the top 10."
        )
    }
  end

  # Formats a count with commas between thousands, e.g. 1234 as "1,234".
  @spec delimit(non_neg_integer()) :: String.t()
  defp delimit(n) when is_integer(n) and n >= 0 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
