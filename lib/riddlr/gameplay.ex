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

  A round always runs its full `solve_time` — the first solve records the First
  solver and nothing else, and `CompleteRiddleWorker` ends the round on the timer.

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

  When a riddle completes, `solve_rows/1` turns the ETS race into rows that
  `Riddlr.Games.transition/3` saves as `Riddlr.Gameplay.Solve`. After that,
  `list_solves/1`, `solve_for/2` and `count_solves/1` read the database, and
  still work after archive drops the ETS rows.

  The 1s cooldown is not atomic — two concurrent submissions can both pass before
  either writes. It is a rate-limiting UX affordance, not a security boundary.
  """

  alias Riddlr.Clock
  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Repo

  import Ecto.Query, only: [from: 2]

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

    answer =
      Answer.new(riddle.id, user, text,
        correct: correct?,
        offset_ms: compute_offset_ms(riddle.live_date)
      )

    store_answer(answer)

    # Placement must follow store_answer/1 — the count includes this row.
    placement = if correct?, do: calculate_placement(riddle.id, answer.timestamp)
    answer = %{answer | placement: placement}

    broadcast_answer(answer)
    moderate_answer_async(answer)

    if correct? do
      points = points_for_placement(placement)
      :ok = Riddlr.Accounts.award_game_points(user.id, placement, points)

      if placement == 1 do
        Riddlr.Games.record_first_solver(
          riddle.id,
          user.id,
          answer.offset_ms && div(answer.offset_ms, 1000)
        )
      end

      {:correct, placement, points}
    else
      :incorrect
    end
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
    |> Enum.any?(&Answer.from_ets(&1).correct)
  end

  @doc """
  How many players have solved a riddle so far. Returns 0 when nobody has
  solved it or it has no answers stored.
  """
  @spec solved_count(integer()) :: non_neg_integer()
  def solved_count(riddle_id) do
    @answers_table
    |> :ets.match_object(Answer.ets_pattern(riddle_id, true))
    |> Enum.uniq_by(&Answer.from_ets(&1).user_id)
    |> length()
  end

  @typedoc "Where a solver finished and the points that place earned."
  @type solve :: %{placement: pos_integer(), points: non_neg_integer()}

  @doc """
  The placement and points a user earned on a live riddle, read from ETS, or
  `nil` if they have not solved it. Lets a player who reloads Play see their
  own result again. Once the riddle completes, use `solve_for/2`.
  """
  @spec live_solve_for(integer(), integer()) :: solve() | nil
  def live_solve_for(riddle_id, user_id) do
    case Enum.find(get_answers(riddle_id), &(&1.correct and &1.user_id == user_id)) do
      nil ->
        nil

      %Answer{placement: placement} ->
        %{placement: placement, points: points_for_placement(placement)}
    end
  end

  defp check_already_solved(riddle_id, user_id) do
    if solved?(riddle_id, user_id), do: {:error, :already_solved}, else: :ok
  end

  # `offset_ms` is stored for leaderboard display only; placement ordering uses
  # the monotonic timestamp, which wall-clock adjustments can't distort.
  defp store_answer(%Answer{} = answer) do
    :ets.insert(@answers_table, Answer.to_ets(answer))
  end

  defp calculate_placement(riddle_id, solve_timestamp) do
    @answers_table
    |> :ets.match_object(Answer.ets_pattern(riddle_id, true))
    |> Enum.count(&(Answer.from_ets(&1).timestamp <= solve_timestamp))
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
  Returns every stored `Answer` for a riddle, newest first, with each correct
  answer carrying the `placement` it earned.

  `username` is nil — ETS doesn't store it. Callers that display answers join
  against `Accounts` themselves.
  """
  def get_answers(riddle_id) do
    @answers_table
    |> :ets.match_object(Answer.ets_pattern(riddle_id))
    |> Enum.map(&Answer.from_ets/1)
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> place_solves()
  end

  # Placement is a position in the whole race, so it has to be read off every
  # answer. Callers that show a windowed feed must not rank the window.
  defp place_solves(answers) do
    placements =
      answers
      |> Enum.filter(& &1.correct)
      |> Enum.sort_by(& &1.timestamp)
      |> Enum.with_index(1)
      |> Map.new(fn {answer, placement} -> {answer.id, placement} end)

    Enum.map(answers, &%{&1 | placement: Map.get(placements, &1.id)})
  end

  @doc """
  Puts an answer — or a post-game chat message — on the riddle's feed.

  Chat rides the same topic and the same message tag so every subscriber picks
  it up without knowing there are two kinds.

  Correct answers go out masked — see `Answer.for_live_feed/1`.
  """
  def broadcast_answer(%Answer{} = answer) do
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      Answer.topic(answer.riddle_id),
      {:answer_submitted, Answer.for_live_feed(answer)}
    )
  end

  defp broadcast_answer_flagged(%Answer{} = answer) do
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      Answer.flagged_topic(answer.riddle_id),
      {:answer_flagged, answer.id}
    )
  end

  # The local blocklist already ran synchronously in Answer.new/4 — this is
  # only the external layer (stubbed today). Fails open, off the submission
  # path — moderation must never block or slow the race, so a flagged answer
  # is retracted from feeds after the fact.
  defp moderate_answer_async(%Answer{} = answer) do
    Task.Supervisor.start_child(Riddlr.TaskSupervisor, fn ->
      case Riddlr.Moderation.check_external(answer.text) do
        {:flagged, _reason} -> broadcast_answer_flagged(answer)
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
  Every solver of a riddle from ETS, as rows ready for `Repo.insert_all/3` into
  `Riddlr.Gameplay.Solve`. Fastest first, placed 1..N, with points 10 down to
  1 and then 0.

  A player counts once, at their earliest correct answer: the already-solved
  guard is not atomic, so two fast correct submissions can both land.

  `Riddlr.Workers.CompleteRiddleWorker` passes these to `Games.transition/3`,
  which saves them in the same transaction as the move to `completed`.
  """
  @spec solve_rows(integer()) :: [map()]
  def solve_rows(riddle_id) do
    now = Clock.utc_now() |> DateTime.truncate(:second)

    @answers_table
    |> :ets.match_object(Answer.ets_pattern(riddle_id, true))
    |> Enum.map(&Answer.from_ets/1)
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.uniq_by(& &1.user_id)
    |> Enum.with_index(1)
    |> Enum.map(fn {answer, placement} ->
      %{
        riddle_id: riddle_id,
        user_id: answer.user_id,
        placement: placement,
        points: points_for_placement(placement),
        solve_time_ms: answer.offset_ms,
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  @doc """
  Every saved solve of a riddle, by placement, with `:user` loaded. Empty
  until the riddle completes.
  """
  @spec list_solves(integer()) :: [Solve.t()]
  def list_solves(riddle_id) do
    from(s in Solve, where: s.riddle_id == ^riddle_id, order_by: s.placement, preload: :user)
    |> Repo.all()
  end

  @doc """
  A user's saved solve of a riddle, or `nil` if they did not solve it or the
  riddle has not completed.
  """
  @spec solve_for(integer(), integer()) :: Solve.t() | nil
  def solve_for(riddle_id, user_id) do
    Repo.get_by(Solve, riddle_id: riddle_id, user_id: user_id)
  end

  @doc "How many solves a riddle has saved. 0 until the riddle completes."
  @spec count_solves(integer()) :: non_neg_integer()
  def count_solves(riddle_id) do
    Repo.aggregate(from(s in Solve, where: s.riddle_id == ^riddle_id), :count)
  end

  @doc """
  Removes all ETS entries for a riddle (call on archive).
  """
  def cleanup_riddle(riddle_id) do
    :ets.match_delete(@answers_table, Answer.ets_pattern(riddle_id))
    :ets.match_delete(@cooldowns_table, {{riddle_id, :_}, :_})
    :ok
  end
end
