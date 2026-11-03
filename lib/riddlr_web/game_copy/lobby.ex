defmodule RiddlrWeb.GameCopy.Lobby do
  @moduledoc """
  The words the Lobby shows: the countdown heading, the room of players and
  the rules.
  """

  import RiddlrWeb.GameCopy, only: [delimit: 1]

  @doc "The flash shown when a player opens a lobby that is not open."
  @spec lobby_unavailable() :: String.t()
  def lobby_unavailable, do: "Game lobby is not yet available."

  @doc "The Lobby's heading, above the clock."
  @spec lobby_heading() :: String.t()
  def lobby_heading, do: "The riddle drops in"

  @doc """
  The words before the drop time in the Lobby's when line, e.g. "Drops for
  everyone today at 1:17pm EST."
  """
  @spec lobby_when_lead() :: String.t()
  def lobby_when_lead, do: "Drops for everyone"

  @doc "The words after the drop time in the Lobby's when line."
  @spec lobby_when_tail() :: String.t()
  def lobby_when_tail,
    do: ""

  @doc "The fact that gives a riddle's solve time, already formatted as a clock."
  @spec solve_time(String.t()) :: String.t()
  def solve_time(clock), do: "#{clock} to solve"

  @doc "The Lobby's call to get ready, shown in the last seconds."
  @spec lobby_ready() :: String.t()
  def lobby_ready, do: "Fingers on the keys"

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
      "Guess as often as you like, one guess per second.",
      "The ten fastest correct answers score, from 10 points down to 1. Spelling counts."
    ]
  end
end
