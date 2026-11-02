defmodule RiddlrWeb.AdminController do
  use RiddlrWeb, :controller
  alias Riddlr.Authorization

  plug :require_admin

  def redirect_to_riddles(conn, _params) do
    redirect(conn, to: ~p"/admin/riddles")
  end

  # A signed-in player who is not an admin gets a 404; the pipeline has sent
  # any guest to log in already. The browser pipeline assigns only
  # :current_scope, never :current_user.
  defp require_admin(conn, _opts) do
    unless Authorization.admin?(conn.assigns.current_scope.user) do
      raise RiddlrWeb.NotFoundError
    end

    conn
  end
end
