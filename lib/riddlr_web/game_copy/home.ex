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
  The Home heading when a riddle is next. It names no time of day, since a
  riddle can drop at any hour.
  """
  @spec hero_heading() :: String.t()
  def hero_heading, do: "Up next"

  @doc "The small line over the Home headline when nothing is next."
  @spec tbd_eyebrow() :: String.t()
  def tbd_eyebrow, do: "Next riddle: TBD"

  @typedoc "A Home headline with nothing next, and its tail."
  @type tbd_headline :: %{text: String.t(), tail: String.t()}

  @tbd_headlines [
    %{text: "What has no clues, no answers, and hasn’t arrived yet?", tail: "The next riddle."},
    %{text: "Your mind may be ready…", tail: "but the next riddle isn’t."},
    %{text: "Silence is the only answer", tail: "(for the time being)."},
    %{text: "Riddle #0: How do you solve a unwritten riddle?", tail: "You don’t."},
    %{text: "Spoiler alert: There’s no next riddle", tail: "(we’re working on it)."}
  ]

  @doc """
  The Home headlines when nothing is next. Home shows one at random. Each
  has a tail, which Home sets apart in colour.
  """
  @spec tbd_headlines() :: [tbd_headline()]
  def tbd_headlines, do: @tbd_headlines

  @doc "The line under the Home headline when nothing is next."
  @spec tbd_lede() :: String.t()
  def tbd_lede, do: "The next riddle hasn’t been announced."

  @doc "The margin note that points at the Home hero card."
  @spec hero_aside() :: String.t()
  def hero_aside, do: "this one"

  @doc """
  The lead of the line under a drop time that gives it in the player's own
  zone, e.g. "Your time: Today at 10:17am PST".
  """
  @spec drop_local_lead() :: String.t()
  def drop_local_lead, do: "Your time:"

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
  def last_unsolved, do: "This one stumped everyone. Nobody cracked it!"

  @doc "The link from the last riddle card to its Results."
  @spec last_link() :: String.t()
  def last_link, do: "View game results and post-game chat"

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
  def hero_teaser_lead, do: "The race is on!"

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
