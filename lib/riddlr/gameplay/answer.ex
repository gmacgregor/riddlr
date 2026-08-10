defmodule Riddlr.Gameplay.Answer do
  @moduledoc """
  An **Answer**: one player's attempt at a riddle, and the unit the race is run on.

  Answers never hit the database. They live in ETS for the length of a game and
  vanish when the riddle is archived. But an answer still shows up in three
  different shapes: the row in ETS, the message broadcast to every player's
  screen, and the id used to yank it back off those screens if moderation
  doesn't like it. All three are built here.

  The id matters more than it looks. It's `riddle-user-timestamp`, and it gets
  built twice: once when you submit, and once when someone else joins the game
  and we replay the feed from ETS. Moderation flags an answer by id, so if those
  two ever disagreed, a flagged answer would stay on the late joiner's screen.
  One function, one scheme, no disagreement.

  Post-game chat is an Answer too, with `chat: true`. Same struct, same topic,
  same feed — the UI doesn't need to know there are two kinds.

  What an Answer deliberately doesn't know: whether it was right (that's the
  riddle's business), what Placement it earned or what it's worth in points
  (`Riddlr.Gameplay` runs the race). It carries the submission; it doesn't judge it.
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
    correct: false,
    flagged: false,
    chat: false,
    show_highlight: false
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          riddle_id: term(),
          user_id: term(),
          username: String.t() | nil,
          text: String.t(),
          timestamp: integer(),
          offset_ms: non_neg_integer() | nil,
          correct: boolean(),
          flagged: boolean(),
          chat: boolean(),
          show_highlight: boolean()
        }

  @doc """
  Builds an answer for `text`, stamped with the monotonic clock.

  Options: `:correct`, `:offset_ms`, `:chat`, and `:timestamp` for callers that
  already took a reading and need the same one on the stored row.
  """
  def new(riddle_id, user, text, opts \\ []) do
    timestamp = Keyword.get_lazy(opts, :timestamp, &Clock.monotonic_us/0)

    %__MODULE__{
      id: id(riddle_id, user.id, timestamp),
      riddle_id: riddle_id,
      user_id: user.id,
      username: user.username,
      text: text,
      timestamp: timestamp,
      offset_ms: Keyword.get(opts, :offset_ms),
      correct: Keyword.get(opts, :correct, false),
      chat: Keyword.get(opts, :chat, false)
    }
  end

  @doc """
  The DOM/stream id an answer is known by, here and in moderation.
  """
  def id(riddle_id, user_id, timestamp), do: "#{riddle_id}-#{user_id}-#{timestamp}"

  @doc """
  The row an answer is stored as in `:riddle_answers` (a `:bag`).

  Positional and undeclared everywhere else; declared here. `solve_time_ms` is
  display data only — placement orders on `timestamp`, which is monotonic and
  so immune to wall-clock adjustment.
  """
  def to_ets(%__MODULE__{} = answer) do
    {{answer.riddle_id, answer.user_id}, answer.text, answer.timestamp, answer.correct,
     answer.offset_ms}
  end

  @doc """
  Rebuilds an answer from its stored row. `username` is not stored — callers
  that need it join against `Accounts`.
  """
  def from_ets({{riddle_id, user_id}, text, timestamp, correct?, solve_time_ms}) do
    %__MODULE__{
      id: id(riddle_id, user_id, timestamp),
      riddle_id: riddle_id,
      user_id: user_id,
      text: text,
      timestamp: timestamp,
      correct: correct?,
      offset_ms: solve_time_ms
    }
  end

  @doc """
  Match pattern for every stored row of a riddle, optionally narrowed to rows
  with a given `correct?` value.
  """
  def ets_pattern(riddle_id, correct? \\ :_), do: {{riddle_id, :_}, :_, :_, correct?, :_}

  @doc """
  Topic every answer and chat message for a riddle is broadcast on.
  """
  def topic(riddle_id), do: "gameplay:#{riddle_id}:answer_submitted"

  @doc """
  Topic a retraction is broadcast on when moderation flags an answer.
  """
  def flagged_topic(riddle_id), do: "gameplay:#{riddle_id}:answer_flagged"
end
