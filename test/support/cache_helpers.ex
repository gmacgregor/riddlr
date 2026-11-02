defmodule Riddlr.CacheHelpers do
  @moduledoc """
  Test helpers for `Riddlr.Cache` and the queries it saves.

  The cache is one table for the whole node and is off in the test config,
  because async tests in different sandboxes would read each other's entries.
  Tests that need it turn it on with `enable_cache/1`, and must be
  `async: false`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Turns the cache on and empties it for one test. Use as a `setup` callback.
  """
  @spec enable_cache(map()) :: :ok
  def enable_cache(_context \\ %{}) do
    config = Application.get_env(:riddlr, Riddlr.Cache)
    Application.put_env(:riddlr, Riddlr.Cache, enabled: true)
    Riddlr.Cache.clear()

    on_exit(fn ->
      Application.put_env(:riddlr, Riddlr.Cache, config)
      Riddlr.Cache.clear()
    end)
  end

  @doc """
  Runs `fun` and returns `{queries, result}`: how many Repo queries ran,
  in any process, while it did.

  Counts every query on the node, so use it only in `async: false` tests.
  """
  @spec count_queries((-> result)) :: {non_neg_integer(), result} when result: var
  def count_queries(fun) do
    counter = :counters.new(1, [])
    handler = "count-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:riddlr, :repo, :query],
      fn _event, _measurements, _meta, counter -> :counters.add(counter, 1, 1) end,
      counter
    )

    try do
      result = fun.()
      {:counters.get(counter, 1), result}
    after
      :telemetry.detach(handler)
    end
  end
end
