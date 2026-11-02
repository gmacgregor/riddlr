defmodule RiddlrWeb.NotFoundError do
  @moduledoc """
  Raised to answer a request with a 404 page.

  The admin pages raise it for a signed-in player who is not an admin, so
  they learn nothing about what lives under /admin.
  """
  defexception message: "not found", plug_status: 404
end
