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
  The Notification text for one player and one riddle, e.g.
  `Kriddle: Riddle No. 42 goes live in 30 min. <link> Info: <info url> Reply
  STOP to end`. A `ready` riddle links to its Lobby; a `scheduled` one to
  Home. `now` sets the minutes left.
  """
  @spec notification(Riddle.t(), User.t(), DateTime.t()) :: Message.t()
  def notification(%Riddle{} = riddle, %User{phone: phone}, %DateTime{} = now)
      when is_binary(phone) do
    info = Application.fetch_env!(:riddlr, :info_url)

    %Message{
      to: phone,
      body:
        "Kriddle: Riddle No. #{riddle.number} goes live in #{Riddlr.Notifications.minutes_left(riddle, now)} minutes. " <>
          "#{link(riddle)} Info: #{info} Reply STOP to end"
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
        "Kriddle: You will get texts before riddles go live. Msg & data rates may apply. " <>
          "Reply STOP to end, HELP for help."
    }
  end
end
