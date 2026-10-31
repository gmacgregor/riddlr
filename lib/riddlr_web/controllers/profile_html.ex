defmodule RiddlrWeb.ProfileHTML do
  use RiddlrWeb, :html

  alias Riddlr.Accounts.User

  embed_templates "profile_html/*"

  @doc """
  Sums up a player's Notification choice in a few words, e.g.
  "Email, 30 min before", or "Off".
  """
  @spec notification_summary(User.t()) :: String.t()
  def notification_summary(%User{notify_email: false}), do: "Off"

  def notification_summary(%User{notification_lead_time: lead_time}),
    do: "Email, " <> lead_time_label(lead_time)

  @spec lead_time_label(User.notification_lead_time()) :: String.t()
  defp lead_time_label(:lobby_open), do: "when the Lobby opens"
  defp lead_time_label(:min_30), do: "30 min before"
  defp lead_time_label(:min_60), do: "1 hour before"
end
