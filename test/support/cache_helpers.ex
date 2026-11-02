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
    {sources, result} = query_sources(fun)
    {length(sources), result}
  end

  @doc """
  Runs `fun` and returns `{sources, result}`: the table each Repo query read,
  in any process, in the order they ran. A query with no table gives `nil`.

  Sees every query on the node, so use it only in `async: false` tests.
  """
  @spec query_sources((-> result)) :: {[String.t() | nil], result} when result: var
  def query_sources(fun) do
    test = self()
    ref = make_ref()
    handler = "query-sources-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:riddlr, :repo, :query],
      fn _event, _measurements, meta, _config -> send(test, {ref, meta.source}) end,
      nil
    )

    result =
      try do
        fun.()
      after
        :telemetry.detach(handler)
      end

    {collect(ref, []), result}
  end

  defp collect(ref, sources) do
    receive do
      {^ref, source} -> collect(ref, [source | sources])
    after
      0 -> Enum.reverse(sources)
    end
  end
end
