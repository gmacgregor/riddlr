defmodule RiddlrWeb.GameCopy.Home do
  @moduledoc """
  The words Home shows: the hero card, the timeline, the schedule, the last
  riddle and the practice riddle.
  """

  import RiddlrWeb.GameCopy, only: [delimit: 1]

  @typedoc """
  The Home hero card's state, one per Next riddle case: nothing next, a
  scheduled riddle whose Lobby is not open, a ready riddle, or a live one.
  """
  @type hero_state :: :none | :future | :lobby | :live

  @doc """
  The Home heading, given the hero state. It names no time of day, since a
  riddle can drop at any hour. With nothing next it promises no riddle.
  """
  @spec hero_heading(hero_state()) :: String.t()
  def hero_heading(:none), do: "Nothing listed"
  def hero_heading(_state), do: "Up next"

  @doc "The margin note that points at the Home hero card."
  @spec hero_aside() :: String.t()
  def hero_aside, do: "this one"

  @doc """
  The lead of the line under a drop time that gives it in the player's own
  zone, e.g. "Your time: Today at 10:17am PST".
  """
  @spec drop_local_lead() :: String.t()
  def drop_local_lead, do: "Your time:"

  @doc "The stamp on the Home card when nothing is next."
  @spec hero_none_stamp() :: String.t()
  def hero_none_stamp, do: "No game scheduled"

  @doc """
  The Home card's heading when nothing is next. It reads "Nothing's
  dropping. Yet.", with the tail on its own so the card can set it apart.
  """
  @spec hero_none_heading() :: String.t()
  def hero_none_heading, do: "Nothing's dropping."

  @doc "The tail of the Home card's heading when nothing is next."
  @spec hero_none_heading_tail() :: String.t()
  def hero_none_heading_tail, do: "Yet."

  @doc "The Home card's line when nothing is next."
  @spec hero_none_text() :: String.t()
  def hero_none_text,
    do: "No riddle is scheduled right now, and the next one hasn't been announced."

  @doc """
  The words before the next drop's time on the Home card when nothing is
  next. The line reads "Next drop: to be announced".
  """
  @spec hero_none_tbc_lead() :: String.t()
  def hero_none_tbc_lead, do: "Next drop:"

  @doc "The next drop's time on the Home card when nothing is next."
  @spec hero_none_tbc() :: String.t()
  def hero_none_tbc, do: "to be announced"

  @doc """
  The words before the link to Coming up in the Home card's note when
  nothing is next. The note reads "New riddles appear in Coming up once
  they're scheduled."
  """
  @spec hero_none_note_lead() :: String.t()
  def hero_none_note_lead, do: "New riddles appear in"

  @doc "The words after the link to Coming up in the Home card's note when nothing is next."
  @spec hero_none_note_tail() :: String.t()
  def hero_none_note_tail, do: "once they're scheduled."

  @doc "The heading of the Home timeline."
  @spec timeline_heading() :: String.t()
  def timeline_heading, do: "How to play"

  @doc """
  The last time on the Home timeline when there is no next riddle. Matches
  the default solve time in `Riddlr.Games.Riddle`.
  """
  @spec timeline_end_default() :: String.t()
  def timeline_end_default, do: "2:00"

  @doc """
  The Home timeline's rows, given the time the round ends (e.g. "2:00"). The
  rows must match the real rules: the 1s cooldown, the exact answer match and
  the points table in `Riddlr.Gameplay`.
  """
  @spec timeline_steps(String.t()) :: [
          %{time: String.t(), title: String.t(), text: String.t(), note: String.t()}
        ]
  def timeline_steps(end_time) do
    [
      %{
        time: "0:00",
        title: "The riddle is revealed",
        text: "Everyone sees it at the same",
        note: "no head starts"
      },
      %{
        time: "0:01",
        title: "Guess away!",
        text: "As often as you like, once per second",
        note: "spelling counts"
      },
      %{
        time: end_time,
        title: "Tick tock…",
        text: "The ten fastest correct answers score, 10 points down to 1",
        note: "think fast, type fast, win points"
      }
    ]
  end

  @doc "The heading of the Home schedule."
  @spec schedule_heading() :: String.t()
  def schedule_heading, do: "Coming up"

  @doc "The Home schedule's line when nothing comes after the next riddle."
  @spec schedule_empty() :: String.t()
  def schedule_empty, do: "Nothing scheduled yet."

  @doc "The heading of the Home card with the last finished riddle."
  @spec last_heading() :: String.t()
  def last_heading, do: "Previously"

  @doc "The last riddle card's line when nobody solved the riddle."
  @spec last_unsolved() :: String.t()
  def last_unsolved, do: "Nobody cracked it"

  @doc "The link from the last riddle card to its Results."
  @spec last_link() :: String.t()
  def last_link, do: "See the board and chat"

  @doc "The last riddle card's title when no riddle has finished."
  @spec last_empty_title() :: String.t()
  def last_empty_title, do: "No riddles solved yet."

  @doc "The last riddle card's line when no riddle has finished."
  @spec last_empty_text() :: String.t()
  def last_empty_text, do: "Answers and winners show here once the first riddle closes."

  @doc "How many players wait in the next riddle's Lobby, e.g. \"12 waiting in the lobby\"."
  @spec hero_waiting(non_neg_integer()) :: String.t()
  def hero_waiting(count), do: "#{delimit(count)} waiting in the lobby"

  @doc "The Home card's label on a live riddle, e.g. \"Live now · Logic\"."
  @spec hero_live(String.t()) :: String.t()
  def hero_live(category), do: "Live now · #{category}"

  @doc "The word after the time left in the Home card's live pill."
  @spec hero_left() :: String.t()
  def hero_left, do: "left"

  @doc """
  The words before the solved count on the Home card's live line. The line
  reads "The race is on. 3 solved so far."; the count stands alone so the
  card can underline it.
  """
  @spec hero_teaser_lead() :: String.t()
  def hero_teaser_lead, do: "The race is on."

  @doc "The solved count on the Home card's live line, e.g. \"1,204\"."
  @spec hero_teaser_count(non_neg_integer()) :: String.t()
  def hero_teaser_count(solved), do: delimit(solved)

  @doc "The words after the solved count on the Home card's live line."
  @spec hero_teaser_tail() :: String.t()
  def hero_teaser_tail, do: "solved so far."

  @doc "The heading of the practice note on Home when nothing is next."
  @spec practice_heading() :: String.t()
  def practice_heading, do: "While you wait…"

  @doc ~S(The practice note's tag, e.g. "Practice riddle 2 of 5".)
  @spec practice_tag(pos_integer(), pos_integer()) :: String.t()
  def practice_tag(n, total), do: "Practice riddle #{delimit(n)} of #{delimit(total)}"

  @doc "The practice note's reminder that it scores nothing."
  @spec practice_note() :: String.t()
  def practice_note, do: ""

  @doc "The button that shows a practice riddle's answer."
  @spec practice_peek() :: String.t()
  def practice_peek, do: "Peek at the answer"

  @doc "The button that hides a practice riddle's answer again."
  @spec practice_hide() :: String.t()
  def practice_hide, do: "Hide it again"

  @doc "The button that swaps in a different practice riddle."
  @spec practice_another() :: String.t()
  def practice_another, do: "Another riddle"

  @doc "What a screen reader hears when the practice answer shows."
  @spec practice_status_shown(String.t()) :: String.t()
  def practice_status_shown(answer), do: "Answer: #{String.downcase(answer)}."

  @doc """
  What a screen reader hears while the practice answer is hidden: how many
  letters and digits it has. Spaces and punctuation do not count.
  """
  @spec practice_status_hidden(String.t()) :: String.t()
  def practice_status_hidden(answer) do
    case ~r/[\p{L}\p{N}]/u |> Regex.scan(answer) |> length() do
      1 -> "Answer hidden, 1 letter."
      count -> "Answer hidden, #{count} letters."
    end
  end
end
