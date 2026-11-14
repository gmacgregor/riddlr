defmodule RiddlrWeb.GameCopy.Results do
  @moduledoc """
  The words the Results screen shows: the board, the payout, the chat and
  the next riddle card.
  """

  import RiddlrWeb.GameCopy, only: [ordinal: 1, m_ss: 1]

  @doc "The divider on Results between the riddle's guesses and the chat."
  @spec chat_divider() :: String.t()
  def chat_divider, do: "Riddle ended"

  @doc """
  The Results chat on an archived riddle. Archive drops the guesses and
  closes chat, so the list is empty.
  """
  @spec chat_archived() :: String.t()
  def chat_archived,
    do:
      "This riddle’s guess history and messages are gone… dust in the wind now, like the fate that awaits us all. ☯"

  @doc "The placeholder in the Results chat field."
  @spec chat_placeholder() :: String.t()
  def chat_placeholder, do: "Type a message…"

  @doc "The words before the time left on the Results chat countdown."
  @spec chat_closes_in_lead() :: String.t()
  def chat_closes_in_lead, do: "Chat closes in"

  @doc "The Results chat countdown, e.g. \"Chat closes in 2:41\"."
  @spec chat_closes_in(non_neg_integer()) :: String.t()
  def chat_closes_in(seconds), do: "#{chat_closes_in_lead()} #{m_ss(seconds)}"

  @doc "The Results chat countdown once it reaches 0 and Archive has not yet arrived."
  @spec chat_closing() :: String.t()
  def chat_closing, do: "Closing…"

  @doc """
  The Results chat countdown given the seconds left: the time, or
  `chat_closing/0` at 0 or below.
  """
  @spec chat_countdown(integer()) :: String.t()
  def chat_countdown(seconds) when seconds > 0, do: chat_closes_in(seconds)
  def chat_countdown(_seconds), do: chat_closing()

  @chat_closed_emojis ["🔒", "🌙", "👋", "🫡", "🎬", "🧹", "💤", "🚪"]

  @doc "Every emoji that can take the Results chat form's place at Archive."
  @spec chat_closed_emojis() :: [String.t()]
  def chat_closed_emojis, do: @chat_closed_emojis

  @doc "A random emoji from `chat_closed_emojis/0`."
  @spec chat_closed_emoji() :: String.t()
  def chat_closed_emoji, do: Enum.random(@chat_closed_emojis)

  @doc "The text left of the emoji that replaces the Results chat form at Archive."
  @spec chat_closed() :: String.t()
  def chat_closed, do: "Chat closed. See you in the next game!"

  @doc "The words before the first solver's name on Results."
  @spec results_by_lead() :: String.t()
  def results_by_lead, do: "Solved first by"

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

  @doc "The link under the Results payout back to Home."
  @spec home_link() :: String.t()
  def home_link, do: "Back to home"

  @doc "The Home card's button to a ready riddle's lobby."
  @spec next_enter_lobby() :: String.t()
  def next_enter_lobby, do: "Enter the lobby"

  @doc "The Home card's button into a live riddle."
  @spec next_jump_in() :: String.t()
  def next_jump_in, do: "Jump in"

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
          do: "+#{points} points for this riddle",
          else: "Solved, but outside the top 10."
        )
    }
  end
end
