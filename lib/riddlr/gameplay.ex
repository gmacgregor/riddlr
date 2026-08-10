defmodule Riddlr.Gameplay do
  @moduledoc """
  The Gameplay context — the Answer race.

  `submit_answer/3` is the only way in. Everything it composes (answer storage,
  placement counting, the points table, feed broadcasts, moderation) is private,
  because the pieces only produce a correct result in one particular order and
  nothing in their signatures says so:

  - placement counts the submitter's own row, so it is only correct *after* the
    answer has been stored; called first it returns `placement - 1`
  - the cooldown check is a check-and-set, so a second call inside the same
    submission burns the player's next second
  - a riddle's `live_until_solved` flag decides whether the first solve completes
    the riddle or merely records the First solver; neither `Games` function guards
    against being called for the wrong riddle type

  Guard order is deliberate: the cooldown runs last so a blank or over-long answer
  is rejected without costing the player their next second.

  Known gap: placement is read from ETS but points are written to Postgres, and
  nothing coordinates the two. A crash in between silently loses the points and
  cannot be retried — the stored answer already makes the player "already solved".

  Ephemeral game state lives in ETS tables:
  - `:riddle_answers` (:bag) — all answer submissions per riddle/user
  - `:answer_cooldowns` (:set) — per-user cooldown timestamps

  Both tables are owned by `Riddlr.Gameplay.EtsOwner` (a supervised GenServer)
  and are recreated automatically if that process restarts. A restart wipes every
  in-flight answer.

  The 1s cooldown is not atomic — two concurrent submissions can both pass before
  either writes. It is a rate-limiting UX affordance, not a security boundary.
  """

  alias Riddlr.Clock

  @answers_table :riddle_answers
  @cooldowns_table :answer_cooldowns
  # 1 second in microseconds
  @cooldown_us 1_000_000
  @answer_max_length 500

  @doc """
  Runs a player's answer through the Answer race.

  Absorbs the whole submission: guards, cooldown, storage, placement, points,
  first solver and the Live-until-solved decision.

  Returns `{:correct, placement, points}`, `:incorrect`, or `{:error, reason}`.
  """
  def submit_answer(riddle, user, text) do
    text = String.trim(text)

    with :ok <- check_not_banned(user),
         :ok <- check_game_live(riddle),
         :ok <- check_already_solved(riddle.id, user.id),
         :ok <- validate_input(text),
         # Mutates — keep last, and call it exactly once per submission.
         :ok <- check_cooldown(riddle.id, user.id) do
      race(riddle, user, text)
    end
  end

  defp check_game_live(%{play_status: "live"}), do: :ok
  defp check_game_live(%{play_status: status}), do: {:error, {:not_live, status}}

  defp check_not_banned(%{account_status: :banned}), do: {:error, :banned}
  defp check_not_banned(_user), do: :ok

  defp validate_input(text) do
    cond do
      text == "" -> {:error, :empty_answer}
      String.length(text) > @answer_max_length -> {:error, :answer_too_long}
      true -> :ok
    end
  end

  defp race(riddle, user, text) do
    correct? = validate_answer(riddle, text)
    solve_time_ms = compute_offset_ms(riddle.live_date)
    timestamp = store_answer(riddle.id, user.id, text, correct?, solve_time_ms)

    answer_data = %{
      id: "#{riddle.id}-#{user.id}-#{timestamp}",
      user_id: user.id,
      username: user.username,
      text: text,
      correct: correct?,
      timestamp: timestamp,
      offset_ms: solve_time_ms,
      show_highlight: false,
      flagged: false,
      chat: false
    }

    broadcast_answer(riddle.id, answer_data)
    moderate_answer_async(riddle.id, answer_data.id, text)

    if correct? do
      # Must follow store_answer/5 — the count includes this submission's row.
      placement = calculate_placement(riddle.id, timestamp)
      points = points_for_placement(placement)
      :ok = Riddlr.Accounts.award_game_points(user.id, placement, points)

      if placement == 1 do
        claim_first_solve(riddle, user, solve_time_ms && div(solve_time_ms, 1000))
      end

      {:correct, placement, points}
    else
      :incorrect
    end
  end

  # Timed riddles keep running and let CompleteRiddleWorker fire at solve_time.
  defp claim_first_solve(%{live_until_solved: true} = riddle, user, first_solve_time_seconds) do
    stats =
      riddle.id
      |> get_completion_stats()
      |> Map.put(:first_solve_time, first_solve_time_seconds)

    Riddlr.Games.complete_riddle_on_first_solve(riddle.id, user.id, stats)
  end

  defp claim_first_solve(riddle, user, first_solve_time_seconds) do
    Riddlr.Games.record_first_solver(riddle.id, user.id, first_solve_time_seconds)
  end

  defp compute_offset_ms(nil), do: nil

  defp compute_offset_ms(live_date) do
    max(DateTime.diff(Clock.utc_now(), live_date, :millisecond), 0)
  end

  defp validate_answer(%{answers: answers}, text) do
    normalized = text |> String.trim() |> String.downcase()
    Enum.any?(answers, fn a -> a |> String.trim() |> String.downcase() == normalized end)
  end

  defp check_cooldown(riddle_id, user_id) do
    now = Clock.monotonic_us()
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
  Returns true if the user has already submitted a correct answer for this riddle.
  """
  def solved?(riddle_id, user_id) do
    @answers_table
    |> :ets.lookup({riddle_id, user_id})
    |> Enum.any?(fn {_key, _text, _ts, correct?, _} -> correct? end)
  end

  defp check_already_solved(riddle_id, user_id) do
    if solved?(riddle_id, user_id), do: {:error, :already_solved}, else: :ok
  end

  # `solve_time_ms` is stored for leaderboard display only; placement ordering
  # uses the monotonic timestamp, which wall-clock adjustments can't distort.
  defp store_answer(riddle_id, user_id, text, correct?, solve_time_ms) do
    timestamp = Clock.monotonic_us()
    :ets.insert(@answers_table, {{riddle_id, user_id}, text, timestamp, correct?, solve_time_ms})
    timestamp
  end

  defp calculate_placement(riddle_id, solve_timestamp) do
    @answers_table
    |> :ets.match_object({{riddle_id, :_}, :_, :_, true, :_})
    |> Enum.count(fn {_key, _text, ts, _, _} -> ts <= solve_timestamp end)
  end

  defp points_for_placement(1), do: 10
  defp points_for_placement(2), do: 9
  defp points_for_placement(3), do: 8
  defp points_for_placement(4), do: 7
  defp points_for_placement(5), do: 6
  defp points_for_placement(6), do: 5
  defp points_for_placement(7), do: 4
  defp points_for_placement(8), do: 3
  defp points_for_placement(9), do: 2
  defp points_for_placement(10), do: 1
  defp points_for_placement(_), do: 0

  @doc """
  Returns all answers for a riddle, sorted by timestamp (newest first).
  Each entry is a map with user_id, text, timestamp, correct fields.
  """
  def get_answers(riddle_id) do
    @answers_table
    |> :ets.match_object({{riddle_id, :_}, :_, :_, :_, :_})
    |> Enum.map(fn {{_rid, user_id}, text, timestamp, correct?, _solve_time_ms} ->
      %{user_id: user_id, text: text, timestamp: timestamp, correct: correct?}
    end)
    |> Enum.sort_by(& &1.timestamp, :desc)
  end

  defp broadcast_answer(riddle_id, answer_data) do
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "gameplay:#{riddle_id}:answer_submitted",
      {:answer_submitted, answer_data}
    )
  end

  @doc """
  Broadcasts a chat message during the cooldown period.
  Reuses the answer_submitted topic so existing subscribers receive it automatically.
  """
  def broadcast_chat(riddle_id, chat_data) do
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "gameplay:#{riddle_id}:answer_submitted",
      {:answer_submitted, chat_data}
    )
  end

  defp broadcast_answer_flagged(riddle_id, answer_id) do
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "gameplay:#{riddle_id}:answer_flagged",
      {:answer_flagged, answer_id}
    )
  end

  # Fails open, off the submission path — moderation must never block or slow
  # the race, so a flagged answer is retracted from feeds after the fact.
  defp moderate_answer_async(riddle_id, answer_id, text) do
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
    |> :ets.match_object({{riddle_id, :_}, :_, :_, true, :_})
    |> Enum.map(fn {{_rid, user_id}, _text, ts, _, solve_time_ms} ->
      {user_id, ts, solve_time_ms}
    end)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.take(limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {{user_id, _ts, solve_time_ms}, placement} ->
      %{
        user_id: user_id,
        placement: placement,
        points: points_for_placement(placement),
        solve_time_ms: solve_time_ms
      }
    end)
  end

  @doc """
  Removes all ETS entries for a riddle (call on archive).
  """
  def cleanup_riddle(riddle_id) do
    :ets.match_delete(@answers_table, {{riddle_id, :_}, :_, :_, :_, :_})
    :ets.match_delete(@cooldowns_table, {{riddle_id, :_}, :_})
    :ok
  end
end
