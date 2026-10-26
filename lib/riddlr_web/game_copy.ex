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
