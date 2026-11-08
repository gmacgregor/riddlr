defmodule RiddlrWeb.ControllerHelpers do
  @moduledoc """
  Plugs shared by all controllers. `use RiddlrWeb, :controller` imports them,
  so a controller can name them in a `plug` call.
  """

  import Plug.Conn

  @doc """
  Function plug: sets the title the browser tab shows.

      plug :put_page_title, "Log in" when action in [:new, :create]
  """
  @spec put_page_title(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put_page_title(conn, title), do: assign(conn, :page_title, "#{title} · Kriddle")
end
