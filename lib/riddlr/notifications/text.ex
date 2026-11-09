defmodule Riddlr.Notifications.Text do
  @moduledoc """
  Builds Notification texts. Never the riddle text. Each fits one GSM-7
  segment (160 characters) and links the info page and says how to stop.
  """

  use Phoenix.VerifiedRoutes, endpoint: RiddlrWeb.Endpoint, router: RiddlrWeb.Router

  alias Riddlr.Accounts.User
  alias Riddlr.Games.Riddle
  alias Riddlr.SMS.Message

  @doc """
  The Notification text for one player and one riddle.
  A `ready` riddle links to its Lobby; a `scheduled` one to
  Home. `now` sets the minutes left.
  """
  @spec notification(Riddle.t(), User.t(), DateTime.t()) :: Message.t()
  def notification(%Riddle{} = riddle, %User{phone: phone}, %DateTime{} = now)
      when is_binary(phone) do
    info = Application.fetch_env!(:riddlr, :info_url)

    %Message{
      to: phone,
      body:
        "Kriddle: Riddle No. #{riddle.number} goes live in #{Riddlr.Notifications.minutes_left(riddle, now)} minutes.\n" <>
          "#{link(riddle)}\nReply STOP to end. Info: #{info}"
    }
  end

  @spec link(Riddle.t()) :: String.t()
  defp link(%Riddle{play_status: "ready", id: id}), do: url(~p"/game/#{id}/lobby")
  defp link(%Riddle{}), do: url(~p"/")

  @doc "The one text sent when a player turns Text on."
  @spec confirmation(User.t()) :: Message.t()
  def confirmation(%User{phone: phone}) when is_binary(phone) do
    %Message{
      to: phone,
      body:
        "Set up complete: you'll receive text messages from Kriddle before riddles go live. Reply STOP to end or disable in your account settings."
    }
  end
end
