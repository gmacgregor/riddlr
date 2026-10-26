defmodule Riddlr.Gameplay.Presence do
  @moduledoc """
  Provides presence tracking for game lobbies.

  Tracks connected players per lobby, broadcasting diffs via PubSub
  whenever players join or leave.
  """
  use Phoenix.Presence,
    otp_app: :riddlr,
    pubsub_server: Riddlr.PubSub

  @doc """
  The topic a riddle's Lobby tracks its players on. Subscribe to it to hear
  `presence_diff` broadcasts as players come and go.
  """
  @spec lobby_topic(integer() | String.t()) :: String.t()
  def lobby_topic(riddle_id), do: "game:lobby:#{riddle_id}"
end
