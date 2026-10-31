defmodule Riddlr.Notifications.Email do
  @moduledoc """
  Builds Notification emails. Plain text only, and never the riddle text.

  Each email carries `List-Unsubscribe` and `List-Unsubscribe-Post` headers
  so mail clients can offer one-click unsubscribe (RFC 8058).
  """

  use Phoenix.VerifiedRoutes, endpoint: RiddlrWeb.Endpoint, router: RiddlrWeb.Router

  import Swoosh.Email

  alias Riddlr.Accounts.User
  alias Riddlr.Games.Riddle

  @doc """
  The Notification email for one player and one riddle. The riddle needs its
  category loaded. `unsubscribe_token` goes in the unsubscribe link; `now`
  sets the minutes left in the subject.

  A `ready` riddle's email links to its Lobby. A `scheduled` riddle has no
  Lobby yet, so its email says when the Lobby opens and links to Home.
  """
  @spec notification(Riddle.t(), User.t(), String.t(), DateTime.t()) :: Swoosh.Email.t()
  def notification(%Riddle{} = riddle, %User{} = user, unsubscribe_token, %DateTime{} = now) do
    unsubscribe_url = url(~p"/notifications/unsubscribe/#{unsubscribe_token}")
    {intro, link} = intro_and_link(riddle)

    new()
    |> to(user.email)
    |> from({"Riddlr", "contact@example.com"})
    |> subject("Riddle No. #{riddle.number} goes live in #{minutes_left(riddle, now)} min")
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> text_body("""
    Hi #{user.username},

    #{intro}

    #{link}

    Have fun and thanks for being a part of the Kriddle community!

    - Team Kriddle

    ---
    You received this update because you turned on email notifications for new Kriddle games. You may disable email notifications here: #{unsubscribe_url}
    """)
  end

  # What the email says before its link, and the link. Only a ready riddle
  # has a Lobby to join.
  @spec intro_and_link(Riddle.t()) :: {String.t(), String.t()}
  defp intro_and_link(%Riddle{play_status: "ready"} = riddle) do
    intro = """
    Get ready! The lobby is open for Kriddle No. #{riddle.number} (#{riddle.category.name}). It goes live on #{display_time(riddle.live_date)}.

    Join here:\
    """

    {intro, url(~p"/game/#{riddle.id}/lobby")}
  end

  defp intro_and_link(%Riddle{} = riddle) do
    lobby_opens = DateTime.add(riddle.live_date, -riddle.ready_before_seconds, :second)

    intro = """
    Kriddle No. #{riddle.number} (#{riddle.category.name}) goes live on #{display_time(riddle.live_date)}. The lobby opens on #{display_time(lobby_opens)}.

    Find it here:\
    """

    {intro, url(~p"/")}
  end

  # Rounded up, so a send a few seconds late still says the full lead time.
  @spec minutes_left(Riddle.t(), DateTime.t()) :: pos_integer()
  defp minutes_left(riddle, now) do
    seconds = DateTime.diff(riddle.live_date, now, :second)
    max(div(seconds + 59, 60), 1)
  end

  @spec display_time(DateTime.t()) :: String.t()
  defp display_time(datetime) do
    zone = Application.fetch_env!(:riddlr, :display_time_zone)

    datetime
    |> DateTime.shift_zone!(zone)
    |> Calendar.strftime("%B %-d, %Y at %-I:%M%P %Z")
  end
end
