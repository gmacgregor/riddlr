defmodule RiddlrWeb.ProfileHTML do
  use RiddlrWeb, :html

  alias Riddlr.Accounts.User

  embed_templates "profile_html/*"

  @doc """
  Sums up a player's Notification choice in a few words, e.g.
  "Email + Text (•••• 1234), 30 min before", or "Off".
  """
  @spec notification_summary(User.t()) :: String.t()
  def notification_summary(%User{} = user) do
    channels =
      [
        user.notify_email && "Email",
        user.notify_sms && user.phone && "Text (#{Riddlr.SMS.mask(user.phone)})"
      ]
      |> Enum.filter(& &1)

    case channels do
      [] -> "Off"
      _ -> Enum.join(channels, " + ") <> ", " <> lead_time_label(user.notification_lead_time)
    end
  end

  @doc """
  An empty `PUT /profile` form for one phone step. Its fields sit elsewhere
  on the page and join it through their `form` attribute. `id` names the
  step and goes in the hidden `action` field.
  """
  attr :id, :string, required: true

  def phone_step_form(assigns) do
    ~H"""
    <.form for={%{}} action={~p"/profile"} method="put" id={@id}>
      <input type="hidden" name="action" value={@id} />
    </.form>
    """
  end

  @spec lead_time_label(User.notification_lead_time()) :: String.t()
  defp lead_time_label(:lobby_open), do: "when the Lobby opens"
  defp lead_time_label(:min_30), do: "30 min before"
  defp lead_time_label(:min_60), do: "1 hour before"
end
