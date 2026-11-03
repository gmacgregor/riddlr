defmodule Riddlr.Gameplay.Answer do
  @moduledoc """
  An **Answer**: one player's attempt at a riddle, and the unit the race is run on.

  Answers never hit the database. They live in ETS for the length of a game and
  vanish when the riddle is archived; `Riddlr.Gameplay.Store` owns the row
  shape. An answer also shows up as the message broadcast to every player's
  screen, and as the id used to yank it back off those screens if moderation
  doesn't like it. Both are built here.

  `new/4` also runs `text` through `Riddlr.Moderation.obfuscate/1` before it's
  stored anywhere, so a banned word never reaches ETS, a broadcast, or
  another player's screen in the first place — there's nothing local
  moderation needs to retract after the fact.

  The id matters more than it looks. It's `riddle-user-timestamp`, and it gets
  built twice: once when you submit, and once when someone else joins the game
  and we replay the feed from ETS. Moderation flags an answer by id, so if those
  two ever disagreed, a flagged answer would stay on the late joiner's screen.
  One function, one scheme, no disagreement.

  Post-game chat is an Answer too, with `chat: true`. Same struct, same topic,
  same feed — the UI doesn't need to know there are two kinds.

  A correct answer is the one thing that must not travel. `for_live_feed/1`
  strips the text before it goes anywhere a player can see, because the round
  keeps running after the first solve and the feed would otherwise hand the
  answer to everyone still guessing. Masking in the template is not enough —
  the string has to be gone from the payload.

  What an Answer deliberately doesn't know: what it's worth in points
  (`Riddlr.Gameplay` runs the race and owns the table). It carries the
  submission and where it finished; it doesn't price it.
  """

  alias Riddlr.Clock

  @enforce_keys [:id, :riddle_id, :user_id, :text, :timestamp]
  defstruct [
    :id,
    :riddle_id,
    :user_id,
    :username,
    :text,
    :timestamp,
    :offset_ms,
    :placement,
    correct: false,
    flagged: false,
    chat: false
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          riddle_id: term(),
          user_id: term(),
          username: String.t() | nil,
          text: String.t() | nil,
          timestamp: integer(),
          offset_ms: non_neg_integer() | nil,
          placement: pos_integer() | nil,
          correct: boolean(),
          flagged: boolean(),
          chat: boolean()
        }

  @doc """
  Builds an answer for `text`, stamped with the monotonic clock.

  Options: `:correct`, `:offset_ms`, `:placement`, `:chat`, and `:timestamp` for
  callers that already took a reading and need the same one on the stored row.
  """
  @spec new(integer(), Riddlr.Accounts.User.t(), String.t(), keyword()) :: t()
  def new(riddle_id, user, text, opts \\ []) do
    timestamp = Keyword.get_lazy(opts, :timestamp, &Clock.monotonic_us/0)

    %__MODULE__{
      id: id(riddle_id, user.id, timestamp),
      riddle_id: riddle_id,
      user_id: user.id,
      username: user.username,
      text: Riddlr.Moderation.obfuscate(text),
      timestamp: timestamp,
      offset_ms: Keyword.get(opts, :offset_ms),
      placement: Keyword.get(opts, :placement),
      correct: Keyword.get(opts, :correct, false),
      chat: Keyword.get(opts, :chat, false)
    }
  end

  @doc """
  The answer as the crowd may see it while the round is still live.

  A correct answer keeps its author, placement and timing but loses its text:
  everyone learns *that* it was solved, nobody learns *what* the answer is.
  Incorrect answers and chat pass through untouched.

  Reveal is simply not calling this — after completion the stored answer is fed
  to the feed as-is.
  """
  @spec for_live_feed(t()) :: t()
  def for_live_feed(%__MODULE__{correct: true} = answer), do: %{answer | text: nil}
  def for_live_feed(%__MODULE__{} = answer), do: answer

  @doc """
  The DOM/stream id an answer is known by, here and in moderation.
  """
  @spec id(integer(), integer(), integer()) :: String.t()
  def id(riddle_id, user_id, timestamp), do: "#{riddle_id}-#{user_id}-#{timestamp}"

  @doc """
  Topic every answer and chat message for a riddle is broadcast on.
  """
  @spec topic(integer()) :: String.t()
  def topic(riddle_id), do: "gameplay:#{riddle_id}:answer_submitted"

  @doc """
  Topic a retraction is broadcast on when moderation flags an answer.
  """
  @spec flagged_topic(integer()) :: String.t()
  def flagged_topic(riddle_id), do: "gameplay:#{riddle_id}:answer_flagged"
end
