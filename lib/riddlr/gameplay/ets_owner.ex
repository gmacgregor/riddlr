defmodule Riddlr.Gameplay.EtsOwner do
  @moduledoc false

  use GenServer

  alias Riddlr.Gameplay.Store

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    :ok = Store.create_tables()
    :ok = Riddlr.Cache.create_table()
    {:ok, []}
  end
end
