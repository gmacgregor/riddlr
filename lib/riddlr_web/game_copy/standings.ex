defmodule RiddlrWeb.GameCopy.Standings do
  @moduledoc """
  The words the Standings page shows: boards, windows, column headings and
  how each board counts.
  """

  @doc "The Standings page heading."
  @spec standings_heading() :: String.t()
  def standings_heading, do: "Leaderboard & stats"

  @doc "The link that opens the note on how each Standings board is counted."
  @spec standings_how_link() :: String.t()
  def standings_how_link, do: "How are these counted?"

  @doc "How one Standings board is counted, for the note under the board."
  @spec standings_how(:points | :wins | :podiums | :fastest) :: String.t()
  def standings_how(:points),
    do:
      "Each solve earns points by place: 10 for 1st, 9 for 2nd, and so on down to 1 for 10th. " <>
        "11th and later earn none. Your total adds up every riddle you solved."

  def standings_how(:wins), do: "How many riddles you solved first."
  def standings_how(:podiums), do: "How many riddles you solved 1st, 2nd or 3rd."

  def standings_how(:fastest),
    do:
      "Your quickest solve on any one riddle: the time from the riddle going live " <>
        "to your right answer."

  @doc "How the Standings note says ties are broken."
  @spec standings_how_ties() :: String.t()
  def standings_how_ties,
    do:
      "Ties: Points looks next at wins, then podiums. Wins looks at podiums, then points. " <>
        "Podiums looks at wins, then points. Fastest looks at which riddle came first. " <>
        "Players still level share a rank."

  @doc "How the Standings note explains This season."
  @spec standings_how_season() :: String.t()
  def standings_how_season,
    do: "This season counts only riddles in the current season, so each season starts from zero."

  @doc "How the Standings note explains This month."
  @spec standings_how_month() :: String.t()
  def standings_how_month,
    do: "This month counts only riddles that went live this calendar month (UTC)."

  @doc "The Standings line when nobody has solved a riddle in the window."
  @spec standings_empty(:all_time | :month | :season) :: String.t()
  def standings_empty(:all_time),
    do: "No one has solved a riddle yet. The first solve puts you on top."

  def standings_empty(:month), do: "No solves yet this month"
  def standings_empty(:season), do: "No solves yet this season"

  @doc "A label on the Standings board switch."
  @spec standings_board(:points | :wins | :podiums | :fastest) :: String.t()
  def standings_board(:points), do: "Points"
  def standings_board(:wins), do: "Wins"
  def standings_board(:podiums), do: "Podiums"
  def standings_board(:fastest), do: "Fastest"

  @doc "The accessible name of the Standings board switch."
  @spec standings_board_label() :: String.t()
  def standings_board_label, do: "Rank standings by"

  @doc "A label on the Standings window switch."
  @spec standings_window(:all_time | :month | :season) :: String.t()
  def standings_window(:season), do: "This season"
  def standings_window(:all_time), do: "All time"
  def standings_window(:month), do: "This month"

  @doc "The accessible name of the Standings window switch."
  @spec standings_window_label() :: String.t()
  def standings_window_label, do: "Show standings for"

  @doc "A Standings column heading."
  @spec standings_col(:rank | :player | :points | :wins | :podiums | :time | :riddle) ::
          String.t()
  def standings_col(:rank), do: "#"
  def standings_col(:player), do: "Player"
  def standings_col(:points), do: "Points"
  def standings_col(:wins), do: "Wins"
  def standings_col(:podiums), do: "Podiums"
  def standings_col(:time), do: "Time"
  def standings_col(:riddle), do: "Riddle"
end
