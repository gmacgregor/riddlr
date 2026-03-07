defmodule Riddlr.Gameplay.Presence do
  @moduledoc """
  Provides presence tracking for game lobbies.

  Tracks connected players per lobby, broadcasting diffs via PubSub
  whenever players join or leave.
  """
  use Phoenix.Presence,
    otp_app: :riddlr,
    pubsub_server: Riddlr.PubSub
end
