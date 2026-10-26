defmodule RiddlrWeb.GameLive.Feed do
  @moduledoc """
  Turns ETS rows into what the game screens show: puts usernames on answer
  and solver rows.
  """

  alias Riddlr.Accounts

  @doc """
  Puts each entry's `:username`. ETS rows hold only the `user_id`, so the
  names come from one batch query. A user who no longer exists shows as
  "Player".
  """
  @spec put_usernames([map()]) :: [map()]
  def put_usernames(entries) do
    users_by_id =
      entries |> Enum.map(& &1.user_id) |> Enum.uniq() |> Accounts.get_users_by_ids()

    Enum.map(entries, fn entry ->
      username =
        case Map.get(users_by_id, entry.user_id) do
          %{username: u} -> u
          nil -> "Player"
        end

      Map.put(entry, :username, username)
    end)
  end
end
