defmodule RiddlrWeb.GameLive.Stagger do
  @moduledoc """
  Spreads out the page change every player makes at the same moment.

  When a riddle goes live or ends, every Lobby or Play view hears the same
  broadcast and moves to the next page. Moving all at once makes every view
  mount the next page in the same instant. `navigate/2` instead waits a random
  time, up to `:max_ms` from config (default 1500), so the mounts spread out.

  The view must handle the `{:stagger_navigate, path}` message it sends
  itself by calling `Phoenix.LiveView.push_navigate/2`. With `:max_ms` at 0 it
  navigates at once.
  """

  @doc """
  Navigates to `path` after a random delay, or at once when the delay is
  turned off.
  """
  @spec navigate(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def navigate(socket, path) do
    case max_ms() do
      0 ->
        Phoenix.LiveView.push_navigate(socket, to: path)

      max_ms ->
        Process.send_after(self(), {:stagger_navigate, path}, :rand.uniform(max_ms))
        socket
    end
  end

  @spec max_ms() :: non_neg_integer()
  defp max_ms do
    :riddlr |> Application.get_env(__MODULE__, []) |> Keyword.get(:max_ms, 1_500)
  end
end
