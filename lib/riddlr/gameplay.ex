defmodule Riddlr.Gameplay do
  @moduledoc """
  The Gameplay context.

  Handles ephemeral game state via ETS tables:
  - `:riddle_answers` (:bag) — all answer submissions per riddle/user
  - `:answer_cooldowns` (:set) — per-user cooldown timestamps

  Both tables are owned by `Riddlr.Gameplay.EtsOwner` (a supervised GenServer)
  and are recreated automatically if that process restarts.
  """

  @answers_table :riddle_answers
  @cooldowns_table :answer_cooldowns
  # 1 second in microseconds
  @cooldown_us 1_000_000

  @doc """
  Validates an answer against the riddle's accepted answers.
  Case-insensitive, trims whitespace.
  Returns true if correct, false otherwise.
  """
  def validate_answer(%{answers: answers}, text) do
    normalized = text |> String.trim() |> String.downcase()
    Enum.any?(answers, fn a -> a |> String.trim() |> String.downcase() == normalized end)
  end

  @doc """
  Checks if the user is in cooldown (submitted within the last second).
  Best-effort check-and-set: records submission timestamp on :ok.
  Not atomic — two concurrent processes could both pass the check before
  either writes. Sufficient for rate-limiting UX; not a security boundary.
  Returns :ok or {:error, :cooldown}.
  """
  def check_cooldown(riddle_id, user_id) do
    now = System.monotonic_time(:microsecond)
    key = {riddle_id, user_id}

    case :ets.lookup(@cooldowns_table, key) do
      [{^key, last_time}] when now - last_time < @cooldown_us ->
        {:error, :cooldown}

      _ ->
        :ets.insert(@cooldowns_table, {key, now})
        :ok
    end
  end

  @doc """
  Checks if the user has already submitted a correct answer for this riddle.
  Returns :ok if not solved, {:error, :already_solved} if they have.
  """
  def check_already_solved(riddle_id, user_id) do
    entries = :ets.lookup(@answers_table, {riddle_id, user_id})

    if Enum.any?(entries, fn {_key, _text, _ts, correct?} -> correct? end) do
      {:error, :already_solved}
    else
      :ok
    end
  end

  @doc """
  Stores an answer submission in ETS.
  Returns the microsecond timestamp of the submission.
  """
  def store_answer(riddle_id, user_id, text, correct?) do
    timestamp = System.monotonic_time(:microsecond)
    :ets.insert(@answers_table, {{riddle_id, user_id}, text, timestamp, correct?})
    timestamp
  end

  @doc """
  Calculates placement for a correct answer based on how many correct answers
  were submitted at or before the given timestamp (1-indexed).
  """
  def calculate_placement(riddle_id, solve_timestamp) do
    @answers_table
    |> :ets.match_object({{riddle_id, :_}, :_, :_, true})
    |> Enum.count(fn {_key, _text, ts, _} -> ts <= solve_timestamp end)
  end

  @doc """
  Returns points for a given placement.
  """
  def points_for_placement(1), do: 10
  def points_for_placement(2), do: 9
  def points_for_placement(3), do: 8
  def points_for_placement(4), do: 7
  def points_for_placement(5), do: 6
  def points_for_placement(6), do: 5
  def points_for_placement(7), do: 4
  def points_for_placement(8), do: 3
  def points_for_placement(9), do: 2
  def points_for_placement(10), do: 1
  def points_for_placement(_), do: 0

  @doc """
  Returns all answers for a riddle, sorted by timestamp (oldest first).
  Each entry is a map with user_id, text, timestamp, correct fields.
  """
  def get_answers(riddle_id) do
    @answers_table
    |> :ets.match_object({{riddle_id, :_}, :_, :_, :_})
    |> Enum.map(fn {{_rid, user_id}, text, timestamp, correct?} ->
      %{user_id: user_id, text: text, timestamp: timestamp, correct: correct?}
    end)
    |> Enum.sort_by(& &1.timestamp)
  end

  @doc """
  Broadcasts an answer submission to the game's answer feed topic.
  """
  def broadcast_answer(riddle_id, answer_data) do
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "gameplay:#{riddle_id}:answer_submitted",
      {:answer_submitted, answer_data}
    )
  end

  @doc """
  Broadcasts that an answer was flagged for content moderation.
  Listeners should remove the answer from their feed.
  """
  def broadcast_answer_flagged(riddle_id, answer_id) do
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "gameplay:#{riddle_id}:answer_flagged",
      {:answer_flagged, answer_id}
    )
  end

  @doc """
  Spawns an async Task.Supervisor child to moderate an answer.
  If flagged, broadcasts `:answer_flagged` so all subscribers can remove it.
  Fails open — moderation errors never block gameplay.
  """
  def moderate_answer_async(riddle_id, answer_id, text) do
    Task.Supervisor.start_child(Riddlr.TaskSupervisor, fn ->
      case Riddlr.Moderation.check(text) do
        {:flagged, _reason} -> broadcast_answer_flagged(riddle_id, answer_id)
        :ok -> :noop
      end
    end)
  end

  @doc """
  Returns game completion stats computed from ETS data.
  Used when transitioning a riddle to :completed.

  Returns:
  - `completion_rate` — percentage of players who submitted a correct answer (0.0–100.0)
  """
  def get_completion_stats(riddle_id) do
    answers = get_answers(riddle_id)
    unique_players = answers |> Enum.map(& &1.user_id) |> Enum.uniq() |> length()

    unique_solvers =
      answers |> Enum.filter(& &1.correct) |> Enum.map(& &1.user_id) |> Enum.uniq() |> length()

    completion_rate =
      if unique_players > 0, do: unique_solvers / unique_players * 100.0, else: 0.0

    %{completion_rate: completion_rate}
  end

  @doc """
  Returns the top `limit` solvers for a riddle, ordered by solve time (fastest first).
  Each entry: %{user_id, placement, points}.
  """
  def get_top_solvers(riddle_id, limit \\ 10) do
    @answers_table
    |> :ets.match_object({{riddle_id, :_}, :_, :_, true})
    |> Enum.map(fn {{_rid, user_id}, _text, ts, _} -> {user_id, ts} end)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.take(limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {{user_id, _ts}, placement} ->
      %{user_id: user_id, placement: placement, points: points_for_placement(placement)}
    end)
  end

  @doc """
  Removes all ETS entries for a riddle (call on archive).
  """
  def cleanup_riddle(riddle_id) do
    :ets.match_delete(@answers_table, {{riddle_id, :_}, :_, :_, :_})
    :ets.match_delete(@cooldowns_table, {{riddle_id, :_}, :_})
    :ok
  end
end
