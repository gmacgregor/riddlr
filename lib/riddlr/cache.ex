defmodule Riddlr.Cache do
  @moduledoc """
  A node-local key-value cache in ETS, for read-heavy pages that many viewers
  load at the same moment: Results, Standings and Home.

  Writers fill an entry when the data changes, before they broadcast that it
  changed, so the viewers who react to the broadcast read a warm entry. A
  reader that misses (after a restart, say) computes the value with `fetch/2`
  and stores it. Every entry can be rebuilt from the database, so losing the
  table loses nothing.

  ETS, not `:persistent_term`: replacing a persistent term makes the VM scan
  every process, and entries change at go-live and completion, the moments
  with the most processes alive.

  The table is owned by `Riddlr.Gameplay.EtsOwner`. Config
  `config :riddlr, Riddlr.Cache, enabled: false` turns the cache off: nothing
  is stored and every `fetch/2` computes.
  """

  @table :riddlr_cache

  @doc "Creates the table. Only `Riddlr.Gameplay.EtsOwner` calls this."
  @spec create_table() :: :ok
  def create_table do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    :ok
  end

  @doc "The value stored under `key`, as `{:ok, value}`, or `:error`."
  @spec get(term()) :: {:ok, term()} | :error
  def get(key) do
    with true <- enabled?(),
         [{^key, value}] <- :ets.lookup(@table, key) do
      {:ok, value}
    else
      _miss -> :error
    end
  end

  @doc "Stores `value` under `key`, replacing any value there."
  @spec put(term(), term()) :: :ok
  def put(key, value) do
    if enabled?(), do: :ets.insert(@table, {key, value})
    :ok
  end

  @doc """
  The value stored under `key`. On a miss, runs `fun`, stores its result and
  returns it. Two readers that miss together both run `fun`; the second
  write wins, and both hold the same data.
  """
  @spec fetch(term(), (-> value)) :: value when value: var
  def fetch(key, fun) do
    case get(key) do
      {:ok, value} ->
        value

      :error ->
        value = fun.()
        put(key, value)
        value
    end
  end

  @doc "Drops the entry under `key`."
  @spec delete(term()) :: :ok
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc "Drops every entry whose key matches `pattern`, an ETS match pattern."
  @spec delete_match(term()) :: :ok
  def delete_match(pattern) do
    :ets.match_delete(@table, {pattern, :_})
    :ok
  end

  @doc "Drops every entry."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec enabled?() :: boolean()
  defp enabled? do
    :riddlr |> Application.get_env(__MODULE__, []) |> Keyword.get(:enabled, true)
  end
end
