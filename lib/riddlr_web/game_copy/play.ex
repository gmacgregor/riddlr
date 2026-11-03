defmodule RiddlrWeb.GameCopy.Play do
  @moduledoc """
  The words the Play screen shows: the guess feed, guess errors and the
  solved panel.
  """

  import RiddlrWeb.GameCopy, only: [delimit: 1, ordinal: 1, m_ss: 1]

  @doc "How many guesses the Play feed holds, e.g. \"12 guesses\"."
  @spec guess_count(non_neg_integer()) :: String.t()
  def guess_count(1), do: "1 guess"
  def guess_count(count), do: "#{delimit(count)} guesses"

  @doc "The Play feed's line when nobody has guessed yet."
  @spec feed_empty() :: String.t()
  def feed_empty, do: "No guesses yet. Be the first to swing."

  @doc "The stamp on a solve in the Play feed, e.g. \"Solved · 2nd\"."
  @spec feed_solved(pos_integer()) :: String.t()
  def feed_solved(placement), do: "Solved · #{ordinal(placement)}"

  @doc "The message when a player sends an empty guess."
  @spec guess_empty() :: String.t()
  def guess_empty, do: "Type an answer first."

  @doc "The message when a player guesses inside the 1s cooldown."
  @spec guess_cooldown() :: String.t()
  def guess_cooldown, do: "One guess per second. Breathe."

  @doc "The message when a guess arrives after the solve time is up."
  @spec guess_time_up() :: String.t()
  def guess_time_up, do: "Time's up. Results are on the way."

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
  def solved_title(_placement, 0), do: "Cracked it, but just off the board."
  def solved_title(placement, _points), do: "Cracked it. #{ordinal(placement)} place."

  @doc """
  The solved panel's line under the title, given the points and the seconds
  left in the round.
  """
  @spec solved_sub(non_neg_integer(), integer()) :: String.t()
  def solved_sub(points, seconds_left),
    do: "+#{points} pts · round closes in #{m_ss(seconds_left)}. Watch the others sweat."
end
