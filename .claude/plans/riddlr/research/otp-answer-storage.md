# OTP Analysis: Game Answer Storage

## Requirement

Track riddle answers (riddle_id → list of {user_id, answer, timestamp, correct?}) with:
- Fast reads (check if user answered correctly)
- Fast writes (append new answer, atomic)
- Placement calculation (1st/2nd/3rd by timestamp)
- No persistence (ephemeral, game duration only)
- Multiple concurrent games (separate per riddle)
- High concurrency (100 simultaneous answers)

## BEAM Architecture Context

- **Concurrency**: YES - 100 users submitting simultaneously requires lock-free reads
- **Isolation**: NO - answers share lifecycle with riddle (cleanup together)
- **Shared state**: YES - multiple readers checking "did user answer?" + writers appending
- **Stateless**: NO - must maintain answer list between submissions

## Recommendation

**Process needed**: NO

**Pattern**: ETS `:public` table with composite keys

**Rationale**: 

ETS perfectly matches requirements:
1. **Lock-free concurrent reads** - `:read_concurrency` eliminates GenServer bottleneck for "already answered?" checks
2. **Atomic writes** - `:ets.insert/2` is atomic, no race conditions
3. **No serialization overhead** - 100 concurrent writes don't queue through single GenServer mailbox
4. **Simple cleanup** - delete all entries by riddle_id when game archives
5. **No process management** - no supervision, no restart strategies, no GenServer boilerplate

GenServer alternative would serialize all operations through single mailbox - bottleneck at scale.

## Implementation

```elixir
defmodule Riddlr.Answers do
  @moduledoc """
  Ephemeral answer storage using ETS.
  Lifecycle: created on app start, cleaned on riddle archival.
  """

  @table_name :riddle_answers

  def init do
    :ets.new(@table_name, [
      :public,
      :bag,  # Multiple answers per riddle_id
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  # Insert answer (atomic)
  def record_answer(riddle_id, user_id, answer, correct?) do
    timestamp = System.system_time(:microsecond)
    :ets.insert(@table_name, {{riddle_id, user_id}, answer, timestamp, correct?})
  end

  # Check if user already answered correctly (lock-free read)
  def already_answered_correctly?(riddle_id, user_id) do
    case :ets.lookup(@table_name, {riddle_id, user_id}) do
      [] -> false
      entries -> Enum.any?(entries, fn {_key, _answer, _ts, correct?} -> correct? end)
    end
  end

  # Get placement (1st/2nd/3rd) - sorts correct answers by timestamp
  def get_placement(riddle_id, user_id) do
    correct_answers =
      :ets.match(@table_name, {{riddle_id, :"$1"}, :"$2", :"$3", true})
      |> Enum.map(fn [uid, answer, ts] -> {uid, answer, ts} end)
      |> Enum.sort_by(fn {_uid, _ans, ts} -> ts end)

    case Enum.find_index(correct_answers, fn {uid, _, _} -> uid == user_id end) do
      nil -> :not_found
      index -> index + 1  # 1-indexed placement
    end
  end

  # Cleanup when riddle archived
  def delete_answers(riddle_id) do
    :ets.match_delete(@table_name, {{riddle_id, :_}, :_, :_, :_})
  end
end
```

## Table Structure

```elixir
# Table type: :bag (multiple entries per key)
# Key: {riddle_id, user_id}
# Value: {answer, timestamp_microseconds, correct?}

# Example entries:
{{1, 42}, "Paris", 1709061234567890, true}
{{1, 42}, "London", 1709061230123456, false}  # Same user, earlier wrong answer
{{1, 99}, "Paris", 1709061235000000, true}
```

## Supervision Tree

```elixir
# In Application.start/2
defmodule Riddlr.Application do
  def start(_type, _args) do
    # Create ETS table before starting children
    Riddlr.Answers.init()

    children = [
      # ... other children
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Testing Approach

```elixir
defmodule Riddlr.AnswersTest do
  use ExUnit.Case

  setup do
    # Tests run in parallel - use unique table per test
    table = :ets.new(:test_answers, [:public, :bag, read_concurrency: true])
    on_exit(fn -> :ets.delete(table) end)
    %{table: table}
  end

  test "concurrent writes", %{table: table} do
    tasks = for i <- 1..100 do
      Task.async(fn ->
        Riddlr.Answers.record_answer(1, i, "answer", true)
      end)
    end

    Enum.each(tasks, &Task.await/1)
    
    # All 100 answers recorded
    assert :ets.info(table, :size) == 100
  end

  test "placement calculation" do
    # Record answers in specific order
    Riddlr.Answers.record_answer(1, 42, "Paris", true)
    :timer.sleep(1)  # Ensure timestamp ordering
    Riddlr.Answers.record_answer(1, 99, "Paris", true)
    
    assert Riddlr.Answers.get_placement(1, 42) == 1
    assert Riddlr.Answers.get_placement(1, 99) == 2
  end
end
```

## Cleanup Strategy

Call `Riddlr.Answers.delete_answers(riddle_id)` when riddle transitions to `:archived` status. No GenServer shutdown, no process lifecycle management needed.

## Performance Characteristics

- **Reads**: O(1) lookup, lock-free with `:read_concurrency`
- **Writes**: O(1) insert, minimal contention with `:write_concurrency`
- **Placement calc**: O(n) where n = correct answers for riddle (acceptable for game-scale data)
- **Memory**: ~100 bytes per answer (ephemeral, cleaned on archive)
- **Concurrency**: 100+ simultaneous operations without serialization

## Alternative Considered: GenServer

**Rejected because**:
- All operations serialize through single mailbox (bottleneck)
- No benefit over ETS for this use case
- Added complexity (supervision, handle_call/cast/info boilerplate)
- Worse performance under high concurrency

GenServer appropriate if we needed:
- Complex coordination (e.g., answer rate limiting with timers)
- External resource management (e.g., database connection pooling)
- Process monitoring (e.g., tracking live user connections)

None apply here - this is pure concurrent data structure operations.
