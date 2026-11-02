defmodule Riddlr.Gameplay.Store do
  @moduledoc """
  The ETS tables that hold a live riddle's race, and every call that touches
  them. No other module names these tables.

  Four tables, split by how they are read:

  - `:riddle_answers` (`:ordered_set`) — every guess, keyed
    `{riddle_id, timestamp, user_id}`, so one riddle's guesses sit together in
    time order and the newest N are a short walk back from the end.
  - `:riddle_players` (`:ordered_set`) — one row per player who guessed, keyed
    `{riddle_id, user_id}`, holding their solve claims, placement and offset.
  - `:riddle_counters` (`:set`) — per-riddle totals of answers, players and
    solves, so no count walks the guesses.
  - `:answer_cooldowns` (`:ordered_set`) — last-guess and last-chat times, keyed
    `{riddle_id, user_id}` and `{riddle_id, {:chat, user_id}}`.

  The riddle id leads every key. An `:ordered_set` only walks part of the table
  when the leading key parts are bound, so a riddle's reads and its cleanup
  never scan other riddles' rows.

  Placement is the order in which correct answers win an atomic counter, not
  their timestamps. Under load a placement can disagree with the timestamp
  order by microseconds; nothing else can disagree with it, because the toast,
  the feed and the saved solve rows all read the stored placement. If a process
  dies between winning its claim and storing its placement, that place is left
  empty. The tables are owned by `Riddlr.Gameplay.EtsOwner`; if it restarts,
  every table is lost together.
  """

  alias Riddlr.Clock
  alias Riddlr.Gameplay.Answer

  @answers :riddle_answers
  @players :riddle_players
  @counters :riddle_counters
  @cooldowns :answer_cooldowns

  @typedoc "A solver: user id, placement, and milliseconds from the live date."
  @type solve :: {integer(), pos_integer(), non_neg_integer() | nil}

  @doc """
  Creates the tables. Only `Riddlr.Gameplay.EtsOwner` calls this, from its
  `init/1`, so the tables live as long as that process.
  """
  @spec create_tables() :: :ok
  def create_tables do
    opts = [:public, :named_table, read_concurrency: true, write_concurrency: true]

    :ets.new(@answers, [:ordered_set | opts])
    :ets.new(@players, [:ordered_set | opts])
    :ets.new(@counters, [:set | opts])
    :ets.new(@cooldowns, [:ordered_set | opts])
    :ok
  end

  @doc """
  Stores a guess. A correct guess also claims the player's solve and takes the
  next placement.

  Returns `{:ok, placement}` for the first correct answer, `{:ok, nil}` for a
  wrong one, and `{:error, :already_solved}` if the player has already solved
  the riddle, in which case nothing is stored. Safe to call from many processes
  at once: exactly one correct answer per player wins, and placements run
  1, 2, 3 with no repeats.
  """
  @spec record(Answer.t()) :: {:ok, pos_integer() | nil} | {:error, :already_solved}
  def record(%Answer{riddle_id: rid, user_id: uid} = answer) do
    key = {rid, uid}

    if :ets.insert_new(@players, {key, 0, nil, nil}), do: bump(rid, :players)

    with {:ok, placement} <- claim(key, answer) do
      :ets.insert(
        @answers,
        {{rid, answer.timestamp, uid}, answer.username, answer.text, answer.correct,
         answer.offset_ms, placement}
      )

      bump(rid, :answers)
      {:ok, placement}
    end
  end

  # update_counter is atomic, so only the first claim sees 1.
  defp claim(_key, %Answer{correct: false}), do: {:ok, nil}

  defp claim({rid, _uid} = key, %Answer{offset_ms: offset_ms}) do
    case :ets.update_counter(@players, key, {2, 1}) do
      1 ->
        placement = bump(rid, :solved)
        :ets.update_element(@players, key, [{3, placement}, {4, offset_ms}])
        {:ok, placement}

      _ ->
        {:error, :already_solved}
    end
  end

  defp bump(rid, counter) do
    key = {rid, counter}
    :ets.update_counter(@counters, key, 1, {key, 0})
  end

  @doc "How many guesses a riddle has stored."
  @spec answer_count(integer()) :: non_neg_integer()
  def answer_count(riddle_id), do: count(riddle_id, :answers)

  @doc "How many players have guessed a riddle."
  @spec player_count(integer()) :: non_neg_integer()
  def player_count(riddle_id), do: count(riddle_id, :players)

  @doc "How many players have solved a riddle."
  @spec solved_count(integer()) :: non_neg_integer()
  def solved_count(riddle_id), do: count(riddle_id, :solved)

  defp count(rid, counter), do: :ets.lookup_element(@counters, {rid, counter}, 2, 0)

  @doc "Whether a player has guessed a riddle."
  @spec guessed?(integer(), integer()) :: boolean()
  def guessed?(riddle_id, user_id), do: :ets.member(@players, {riddle_id, user_id})

  @doc "Whether a player has claimed a solve of a riddle."
  @spec solved?(integer(), integer()) :: boolean()
  def solved?(riddle_id, user_id) do
    :ets.lookup_element(@players, {riddle_id, user_id}, 2, 0) > 0
  end

  @doc """
  A player's placement and offset on a riddle, or `nil` if they have not
  solved it, or have claimed a solve whose placement is not stored yet.
  """
  @spec solve_for(integer(), integer()) ::
          %{placement: pos_integer(), offset_ms: non_neg_integer() | nil} | nil
  def solve_for(riddle_id, user_id) do
    case :ets.lookup(@players, {riddle_id, user_id}) do
      [{_key, _claims, placement, offset_ms}] when is_integer(placement) ->
        %{placement: placement, offset_ms: offset_ms}

      _ ->
        nil
    end
  end

  @doc """
  A riddle's guesses, newest first, at most `limit` of them. Correct answers
  carry their placement.
  """
  @spec recent_answers(integer(), pos_integer() | :infinity) :: [Answer.t()]
  def recent_answers(riddle_id, limit \\ :infinity)

  def recent_answers(riddle_id, :infinity) do
    @answers |> :ets.select_reverse(answers_spec(riddle_id)) |> Enum.map(&to_answer/1)
  end

  def recent_answers(riddle_id, limit) do
    case :ets.select_reverse(@answers, answers_spec(riddle_id), limit) do
      {rows, _continuation} -> Enum.map(rows, &to_answer/1)
      :"$end_of_table" -> []
    end
  end

  defp answers_spec(rid), do: [{{{rid, :_, :_}, :_, :_, :_, :_, :_}, [], [:"$_"]}]

  defp to_answer({{rid, ts, uid}, username, text, correct?, offset_ms, placement}) do
    %Answer{
      id: Answer.id(rid, uid, ts),
      riddle_id: rid,
      user_id: uid,
      username: username,
      text: text,
      timestamp: ts,
      correct: correct?,
      offset_ms: offset_ms,
      placement: placement
    }
  end

  @doc "Every solver of a riddle, by placement."
  @spec solves(integer()) :: [solve()]
  def solves(riddle_id) do
    @players
    |> :ets.select([
      {{{riddle_id, :"$1"}, :_, :"$2", :"$3"}, [{:is_integer, :"$2"}], [{{:"$1", :"$2", :"$3"}}]}
    ])
    |> Enum.sort_by(&elem(&1, 1))
  end

  @doc "The user id of every player who guessed a riddle."
  @spec players(integer()) :: [integer()]
  def players(riddle_id) do
    :ets.select(@players, [{{{riddle_id, :"$1"}, :_, :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Starts a cooldown under `key` unless one started less than `window_us`
  microseconds ago.

  Check and set are two calls, so two processes can both pass at once. The
  cooldown slows players down; it does not guard anything.
  """
  @spec claim_cooldown(term(), non_neg_integer()) :: :ok | {:error, :cooldown}
  def claim_cooldown(key, window_us) do
    now = Clock.monotonic_us()

    case :ets.lookup(@cooldowns, key) do
      [{^key, last}] when now - last < window_us ->
        {:error, :cooldown}

      _ ->
        :ets.insert(@cooldowns, {key, now})
        :ok
    end
  end

  @doc "Drops every row a riddle has in every table."
  @spec cleanup_riddle(integer()) :: :ok
  def cleanup_riddle(riddle_id) do
    :ets.select_delete(@answers, [{{{riddle_id, :_, :_}, :_, :_, :_, :_, :_}, [], [true]}])
    :ets.select_delete(@players, [{{{riddle_id, :_}, :_, :_, :_}, [], [true]}])
    :ets.select_delete(@cooldowns, [{{{riddle_id, :_}, :_}, [], [true]}])
    Enum.each([:answers, :players, :solved], &:ets.delete(@counters, {riddle_id, &1}))
    :ok
  end
end
