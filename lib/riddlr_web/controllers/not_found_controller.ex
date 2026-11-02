defmodule RiddlrWeb.NotFoundController do
  @moduledoc """
  Answers every path no other route claims with a 404.

  The catch-all route sends unknown pages here through the browser pipeline,
  so the 404 page knows the player's colour mode and account. Without it,
  Phoenix raises before any pipeline runs and the page shows a guest.
  """
  use RiddlrWeb, :controller

  @spec show(Plug.Conn.t(), map()) :: no_return()
  def show(_conn, _params), do: raise(RiddlrWeb.NotFoundError)
end
