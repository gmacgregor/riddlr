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

  @doc "How many players wait in the Lobby."
  @spec players_waiting(non_neg_integer()) :: String.t()
  def players_waiting(1), do: "1 player waiting"
  def players_waiting(count), do: "#{count} players waiting"

  # ─── Clock ────────────────────────────────────────────────────────────────────

  @doc """
  The words after the time in the split-flap clock's screen-reader label,
  e.g. "02:05 until the riddle starts".
  """
  @spec clock_label_tail() :: String.t()
  def clock_label_tail, do: "until the riddle starts"
end
