defmodule Riddlr.Gameplay do
  @moduledoc """
  The Gameplay context — the Answer race.

  `submit_answer/3` is the only way in. Everything it composes (answer storage,
  placement, the points table, feed broadcasts, moderation) is private. The
  cooldown check is a check-and-set, so a second call inside the same
  submission burns the player's next second.

  A round always runs its full `solve_time` — the first solve records the First
  solver and nothing else, and `CompleteRiddleWorker` ends the round on the timer.

  Guard order is deliberate: the cooldown runs last so a blank or over-long answer
  is rejected without costing the player their next second.

  Known gap: placement is read from ETS but points are written to Postgres, and
  nothing coordinates the two. A crash in between silently loses the points and
  cannot be retried — the stored answer already makes the player "already solved".

  Live game state lives in ETS, behind `Riddlr.Gameplay.Store`, which also
  explains how placement is decided. Cooldowns are keyed `{riddle_id, user_id}`
  for guesses and `{riddle_id, {:chat, user_id}}` for chat, so a chat never
  costs a guess and `cleanup_riddle/1` drops both. A restart of
  `Riddlr.Gameplay.EtsOwner` wipes every in-flight answer.

  When a riddle completes, `solve_rows/1` and `entry_rows/1` turn the ETS race
  into rows, and `persist_results/3` adds the steps that save them as
  `Riddlr.Gameplay.Solve` and `Riddlr.Gameplay.Entry` to the transaction
  `Riddlr.Games.transition/3` runs. After that,
  `list_solves/1`, `solve_for/2` and `count_solves/1` read the database, and
  still work after archive drops the ETS rows.

  The 1s cooldown is not atomic — two concurrent submissions can both pass before
  either writes. It is a rate-limiting UX affordance, not a security boundary.
  """

  alias Ecto.Multi
  alias Riddlr.Cache
  alias Riddlr.Clock
  alias Riddlr.Gameplay.Answer
  alias Riddlr.Gameplay.Entry
  alias Riddlr.Gameplay.Solve
  alias Riddlr.Gameplay.Store
  alias Riddlr.Repo

  import Ecto.Query, only: [from: 2]

  # 1 second in microseconds
  @cooldown_us 1_000_000
  @answer_max_length 500
  # Postgres caps one statement at 65,535 bound parameters. A solve row binds
  # 7, so one insert of more than ~9,300 solvers fails.
  @result_row_chunk 5_000
  # Results shows this many solvers, plus the viewer's own row if lower down.
  @board_limit 50

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
         :ok <- check_time_left(riddle),
         :ok <- check_already_solved(riddle.id, user.id),
         :ok <- validate_input(text),
         # Mutates — keep last, and call it exactly once per submission.
         :ok <- check_cooldown({riddle.id, user.id}) do
      race(riddle, user, text)
    end
  end

  @doc """
  Puts a post-game chat message on the riddle's feed.

  Chat has its own 1s cooldown per user, apart from the guess cooldown. The
  caller checks the text first.

  Returns `:ok` or `{:error, :cooldown}`.
  """
  @spec send_chat(Riddlr.Games.Riddle.t(), Riddlr.Accounts.User.t(), String.t()) ::
          :ok | {:error, :cooldown}
  def send_chat(riddle, user, text) do
    with :ok <- check_cooldown({riddle.id, {:chat, user.id}}) do
      broadcast_answer(Answer.new(riddle.id, user, text, chat: true))
    end
  end

  defp check_game_live(%{play_status: "live"}), do: :ok
  defp check_game_live(%{play_status: status}), do: {:error, {:not_live, status}}

  # A riddle still reads "live" for a moment after its timer runs out, until
  # CompleteRiddleWorker ends the round, and the caller's struct may be older
  # still. The clock decides, so no guess gets in late. It checks to the
  # millisecond, not by GameClock.countdown/1: the countdown rounds down and
  # shows 0 for the last second, which would cut that second from the round.
  @spec check_time_left(Riddlr.Games.Riddle.t()) :: :ok | {:error, :time_up}
  defp check_time_left(%{live_date: nil}), do: :ok

  defp check_time_left(riddle) do
    now = Clock.utc_now()
    deadline = DateTime.add(riddle.live_date, riddle.solve_time, :second)

    if DateTime.before?(now, riddle.live_date) or not DateTime.before?(now, deadline),
      do: {:error, :time_up},
      else: :ok
  end

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

    # The early already-solved check is not atomic; Store.record/1 is.
    with {:ok, placement} <- Store.record(answer) do
      answer = %{answer | placement: placement}

      Riddlr.GameClock.push_answer(answer)
      moderate_answer_async(answer)
      score(riddle, user, answer)
    end
  end

  defp score(_riddle, _user, %Answer{correct: false}), do: :incorrect

  defp score(riddle, user, %Answer{placement: placement} = answer) do
    if placement == 1 do
      Riddlr.Games.record_first_solver(riddle.id, user.id, answer.offset_ms)
    end

    {:correct, placement, points_for_placement(placement)}
  end

  defp compute_offset_ms(nil), do: nil

  defp compute_offset_ms(live_date) do
    max(DateTime.diff(Clock.utc_now(), live_date, :millisecond), 0)
  end

  defp validate_answer(%{answers: answers}, text) do
    normalized = text |> String.trim() |> String.downcase()
    Enum.any?(answers, fn a -> a |> String.trim() |> String.downcase() == normalized end)
  end

  @spec check_cooldown({integer(), term()}) :: :ok | {:error, :cooldown}
  defp check_cooldown(key), do: Store.claim_cooldown(key, @cooldown_us)

  @doc """
  Returns true if the user has already submitted a correct answer for this riddle.
  """
  @spec solved?(integer(), integer()) :: boolean()
  defdelegate solved?(riddle_id, user_id), to: Store

  @doc """
  Returns true if the user has submitted any answer to this riddle. Reads ETS,
  so it turns false once archive drops the riddle's answers.
  """
  @spec guessed?(integer(), integer()) :: boolean()
  defdelegate guessed?(riddle_id, user_id), to: Store

  @doc """
  How many players have solved a riddle so far. Returns 0 when nobody has
  solved it or it has no answers stored.
  """
  @spec solved_count(integer()) :: non_neg_integer()
  defdelegate solved_count(riddle_id), to: Store

  @doc "How many guesses a riddle has stored. 0 once archive drops them."
  @spec answer_count(integer()) :: non_neg_integer()
  defdelegate answer_count(riddle_id), to: Store

  @typedoc "Where a solver finished and the points that place earned."
  @type solve :: %{placement: pos_integer(), points: non_neg_integer()}

  @doc """
  The placement and points a user earned on a live riddle, read from ETS, or
  `nil` if they have not solved it. Lets a player who reloads Play see their
  own result again. Once the riddle completes, use `solve_for/2`.
  """
  @spec live_solve_for(integer(), integer()) :: solve() | nil
  def live_solve_for(riddle_id, user_id) do
    case Store.solve_for(riddle_id, user_id) do
      nil -> nil
      %{placement: placement} -> %{placement: placement, points: points_for_placement(placement)}
    end
  end

  defp check_already_solved(riddle_id, user_id) do
    if solved?(riddle_id, user_id), do: {:error, :already_solved}, else: :ok
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
  The points each scoring place earns, from 1st to 10th. Places after 10th
  earn nothing.
  """
  @spec points_table() :: [pos_integer()]
  def points_table, do: Enum.map(1..10, &points_for_placement/1)

  @doc """
  A riddle's stored answers, newest first, at most `limit` of them. Each
  carries the username it was sent under, and each correct answer the
  placement it earned.
  """
  @spec get_answers(integer(), pos_integer() | :infinity) :: [Answer.t()]
  defdelegate get_answers(riddle_id, limit \\ :infinity), to: Store, as: :recent_answers

  @doc """
  A riddle's newest answers, at most `limit`, oldest first and with correct
  answers masked as on the live feed (`Answer.for_live_feed/1`). A viewer
  that joins mid-race starts its feed from this.
  """
  @spec get_live_feed(integer(), pos_integer()) :: [Answer.t()]
  def get_live_feed(riddle_id, limit) do
    riddle_id
    |> get_answers(limit)
    |> Enum.reverse()
    |> Enum.map(&Answer.for_live_feed/1)
  end

  @doc """
  Subscribes the caller to a riddle's live feed: answer batches from
  `broadcast_answers/2` and flags on answers already shown.
  """
  @spec subscribe_answers(integer()) :: :ok | {:error, term()}
  def subscribe_answers(riddle_id) do
    with :ok <- Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(riddle_id)) do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.flagged_topic(riddle_id))
    end
  end

  @doc """
  Puts guesses on a riddle's live feed in one message, oldest first, with the
  riddle's guess and solve totals as they stand now:

      {:answers_batch, answers, %{guesses: n, solved: m}}

  The totals cover every guess stored, not only the batch, so a viewer sets
  its counts from them rather than adding. `Riddlr.GameClock.push_answer/1`
  decides when to call this.

  Correct answers go out masked — see `Answer.for_live_feed/1`.
  """
  @spec broadcast_answers(integer(), [Answer.t()]) :: :ok | {:error, term()}
  def broadcast_answers(riddle_id, answers) do
    totals = %{guesses: Store.answer_count(riddle_id), solved: Store.solved_count(riddle_id)}

    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      Answer.topic(riddle_id),
      {:answers_batch, Enum.map(answers, &Answer.for_live_feed/1), totals}
    )
  end

  @doc """
  Puts a post-game chat message on the riddle's feed, alone and at once. Chat
  is rate-limited per player and not stored, so it skips the guess batch.

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
  # is retracted from feeds after the fact. When the supervisor is full the
  # check is skipped, and a [:riddlr, :moderation, :dropped] event counts it.
  @spec moderate_answer_async(Answer.t()) :: :ok
  defp moderate_answer_async(%Answer{} = answer) do
    task = fn ->
      case Riddlr.Moderation.check_external(answer.text) do
        {:flagged, _reason} -> broadcast_answer_flagged(answer)
        :ok -> :noop
      end
    end

    case Task.Supervisor.start_child(Riddlr.ModerationSupervisor, task) do
      {:ok, _pid} ->
        :ok

      {:error, :max_children} ->
        :telemetry.execute([:riddlr, :moderation, :dropped], %{count: 1}, %{
          riddle_id: answer.riddle_id
        })
    end
  end

  @doc """
  Returns game completion stats computed from ETS data.
  Used when transitioning a riddle to :completed.

  Returns:
  - `completion_rate` — percentage of players who submitted a correct answer (0.0–100.0)
  """
  def get_completion_stats(riddle_id) do
    players = Store.player_count(riddle_id)

    completion_rate =
      if players > 0, do: Store.solved_count(riddle_id) / players * 100.0, else: 0.0

    %{completion_rate: completion_rate}
  end

  @doc """
  Every solver of a riddle from ETS, as rows ready for `Repo.insert_all/3` into
  `Riddlr.Gameplay.Solve`. In placement order, with points 10 down to 1 and
  then 0.

  `Riddlr.Workers.CompleteRiddleWorker` passes these to `Games.transition/3`,
  which saves them with `persist_results/3` in the same transaction as the
  move to `completed`.
  """
  @spec solve_rows(integer()) :: [map()]
  def solve_rows(riddle_id) do
    now = Clock.utc_now() |> DateTime.truncate(:second)

    riddle_id
    |> Store.solves()
    |> Enum.map(fn {user_id, placement, offset_ms} ->
      %{
        riddle_id: riddle_id,
        user_id: user_id,
        placement: placement,
        points: points_for_placement(placement),
        solve_time_ms: offset_ms,
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  @doc """
  Every player who guessed a riddle, from ETS, as rows ready for
  `Repo.insert_all/3` into `Riddlr.Gameplay.Entry`. One row per player,
  solvers included.

  `Riddlr.Workers.CompleteRiddleWorker` passes these to `Games.transition/3`
  with the solve rows.
  """
  @spec entry_rows(integer()) :: [map()]
  def entry_rows(riddle_id) do
    now = Clock.utc_now() |> DateTime.truncate(:second)

    riddle_id
    |> Store.players()
    |> Enum.map(&%{riddle_id: riddle_id, user_id: &1, inserted_at: now, updated_at: now})
  end

  @doc """
  Adds the steps that save a completed riddle's solve and entry rows to
  `multi`. `stats` holds the rows from `solve_rows/1` and `entry_rows/1` under
  `:solves` and `:entries`; either may be missing or empty.

  Postgres caps one statement at 65,535 parameters, so the rows go in batches
  of `:chunk_size` (default #{@result_row_chunk}), one step each, named
  `{:solves, n}` and `{:entries, n}`. Rows already saved are skipped, so a
  second run writes nothing twice.
  """
  @spec persist_results(Multi.t(), map(), keyword()) :: Multi.t()
  def persist_results(multi, stats, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @result_row_chunk)

    multi
    |> insert_chunks(:solves, Solve, Map.get(stats, :solves, []), chunk_size)
    |> insert_chunks(:entries, Entry, Map.get(stats, :entries, []), chunk_size)
  end

  @spec insert_chunks(Multi.t(), :solves | :entries, module(), [map()], pos_integer()) ::
          Multi.t()
  defp insert_chunks(multi, key, schema, rows, chunk_size) do
    rows
    |> Enum.chunk_every(chunk_size)
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {chunk, n}, multi ->
      Multi.insert_all(multi, {key, n}, schema, chunk, on_conflict: :nothing)
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
  A riddle's saved placement-1 solve, or `nil` if nobody solved it or it has
  not completed. `:user` is loaded with only its `id` and `username`, or nil
  for a deleted account.
  """
  @spec first_solve(integer()) :: Solve.t() | nil
  def first_solve(riddle_id) do
    users = from(u in Riddlr.Accounts.User, select: struct(u, [:id, :username]))

    from(s in Solve,
      where: s.riddle_id == ^riddle_id and s.placement == 1,
      preload: [user: ^users]
    )
    |> Repo.one()
  end

  @typedoc """
  One row of a Results board. `username` is nil when the account is gone.
  """
  @type board_row :: %{
          user_id: integer() | nil,
          username: String.t() | nil,
          placement: pos_integer(),
          points: non_neg_integer(),
          solve_time_ms: non_neg_integer() | nil
        }

  @typedoc "The top of a riddle's saved solves, by placement, and how many there are."
  @type board :: %{top: [board_row()], total: non_neg_integer()}

  @doc """
  The first #{@board_limit} saved solves of a riddle, by placement, with
  usernames, and the count of all its solves. Always reads the database; see
  `board/1` for the cached read.
  """
  @spec list_board(integer()) :: board()
  def list_board(riddle_id) do
    top =
      from(s in Solve,
        left_join: u in assoc(s, :user),
        where: s.riddle_id == ^riddle_id,
        order_by: s.placement,
        limit: @board_limit,
        select: %{
          user_id: s.user_id,
          username: u.username,
          placement: s.placement,
          points: s.points,
          solve_time_ms: s.solve_time_ms
        }
      )
      |> Repo.all()

    total = if length(top) < @board_limit, do: length(top), else: count_solves(riddle_id)
    %{top: top, total: total}
  end

  @doc """
  A riddle's Results board (`list_board/1`).

  A completed riddle's board is cached: `warm_board/1` fills it when the
  riddle completes, before every Play view is told to move to Results, and
  `cleanup_riddle/1` drops it at archive. A miss reads the database and fills
  the cache. An archived riddle's board is read from the database every time,
  so no entry outlives the archive.

  A cached board keeps the usernames it was read with until archive.
  """
  @spec board(Riddlr.Games.Riddle.t()) :: board()
  def board(%{play_status: "completed", id: id}) do
    Cache.fetch(board_key(id), fn -> list_board(id) end)
  end

  def board(%{id: id}), do: list_board(id)

  @doc """
  A completed riddle's board if the cache holds it, else `nil`. Never reads
  the database, for a first render that must not.
  """
  @spec cached_board(Riddlr.Games.Riddle.t()) :: board() | nil
  def cached_board(%{play_status: "completed", id: id}) do
    case Cache.get(board_key(id)) do
      {:ok, board} -> board
      :error -> nil
    end
  end

  def cached_board(_riddle), do: nil

  @doc "Reads a riddle's board and stores it in the cache. See `board/1`."
  @spec warm_board(integer()) :: :ok
  def warm_board(riddle_id), do: Cache.put(board_key(riddle_id), list_board(riddle_id))

  defp board_key(riddle_id), do: {:results, riddle_id}

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
  Removes all ETS entries for a riddle, its cached board included (call on
  archive and delete).
  """
  @spec cleanup_riddle(integer()) :: :ok
  def cleanup_riddle(riddle_id) do
    Cache.delete(board_key(riddle_id))
    Store.cleanup_riddle(riddle_id)
  end
end
