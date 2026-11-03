defmodule RiddlrWeb.GameCopy do
  @moduledoc """
  The words the player screens show.

  Templates, components and tests read copy from here, so a wording change
  happens in one place and the tests follow it. Each screen's words live in
  its own module (`RiddlrWeb.GameCopy.Home`, `.Lobby`, `.Play`, `.Results`,
  `.Standings`, `.Errors`). This module holds the words more than one screen
  shows, and the number formats.
  """

  @doc """
  A riddle's number, name and category, e.g. "No. 12: Echo · What am I". A
  riddle with no number yet leaves it out. Takes any map with `number`,
  `name` and `category.name`.
  """
  @spec riddle_title(map()) :: String.t()
  def riddle_title(%{category: %{name: category}} = riddle),
    do: "#{riddle_name(riddle)} · #{category}"

  @doc """
  A riddle's number and name, e.g. "No. 12: Echo", or just the name when it
  has no number yet.
  """
  @spec riddle_name(map()) :: String.t()
  def riddle_name(%{number: nil, name: name}), do: name
  def riddle_name(%{number: number, name: name}), do: "No. #{number}: #{name}"

  @doc "The link in the Home join note that goes to log in."
  @spec join_log_in() :: String.t()
  def join_log_in, do: "Log in"

  @doc "The word between the Home join note's two links."
  @spec join_or() :: String.t()
  def join_or, do: "or"

  @doc "The link in the Home join note that goes to sign up."
  @spec join_sign_up() :: String.t()
  def join_sign_up, do: "sign up"

  @doc "The end of the Home join note, after its links."
  @spec join_tail() :: String.t()
  def join_tail, do: "to play"

  @doc """
  The words after the time in the split-flap clock's screen-reader label,
  e.g. "02:05 until the riddle starts".
  """
  @spec clock_label_tail() :: String.t()
  def clock_label_tail, do: "until the riddle starts"

  @doc "The screen-reader label of a blank split-flap clock: nothing is scheduled."
  @spec clock_blank_label() :: String.t()
  def clock_blank_label, do: "No riddle scheduled, so no countdown"

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

  @doc "How many players have solved the riddle, e.g. \"3 solved\"."
  @spec solved_count(non_neg_integer()) :: String.t()
  def solved_count(count), do: "#{delimit(count)} solved"

  @doc """
  A solve time in seconds with two decimals, e.g. 3456 ms as "3.46s". A
  hundredth of a second can split two places, so one decimal is not enough.
  A solve with no time (the riddle had no live date) reads "—".
  """
  @spec solve_secs(non_neg_integer() | nil) :: String.t()
  def solve_secs(nil), do: "—"

  # Integer maths, so no float rounding shows in the digits.
  def solve_secs(ms) when is_integer(ms) do
    cs = div(max(ms, 0) + 5, 10)
    "#{div(cs, 100)}.#{cs |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}s"
  end

  @doc "The name shown for a player whose account is gone."
  @spec gone_player() :: String.t()
  def gone_player, do: "Player"

  @doc "The link to the Standings page from Home and Results."
  @spec standings_link() :: String.t()
  def standings_link, do: "Leaderboard & game stats"

  @doc """
  Formats a count with commas between thousands, e.g. 1234 as "1,234".
  """
  @spec delimit(non_neg_integer()) :: String.t()
  def delimit(n) when is_integer(n) and n >= 0 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
