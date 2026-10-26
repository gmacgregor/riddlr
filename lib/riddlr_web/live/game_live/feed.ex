defmodule RiddlrWeb.GameLive.Feed do
  @moduledoc """
  Turns ETS rows into what the game screens show: puts usernames on answer
  and solver rows, and formats seconds as clock time.
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

  @doc """
  Formats seconds as `MM:SS`.

      iex> RiddlrWeb.GameLive.Feed.format_time(75)
      "01:15"
  """
  @spec format_time(non_neg_integer()) :: String.t()
  def format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end
end
