defmodule RiddlrWeb.UnsubscribeController do
  @moduledoc """
  One-click unsubscribe from Notification emails, no login needed.

  GET shows a page with one button, so mail scanners that fetch links do not
  turn email off. POST turns it off; mail clients POST here straight from the
  `List-Unsubscribe-Post` header, so this route has no CSRF check.
  """
  use RiddlrWeb, :controller

  alias Riddlr.Notifications

  @doc "Shows the turn-off button, or an error for a bad token."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"token" => token}) do
    render(conn, :show,
      token: token,
      valid?: match?({:ok, _}, Notifications.verify_unsubscribe_token(token))
    )
  end

  @doc "Turns email Notifications off for the player in the token."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"token" => token}) do
    case Notifications.unsubscribe(token) do
      {:ok, _user} ->
        render(conn, :done)

      {:error, :invalid} ->
        conn
        |> put_status(:bad_request)
        |> render(:show, token: token, valid?: false)
    end
  end
end
