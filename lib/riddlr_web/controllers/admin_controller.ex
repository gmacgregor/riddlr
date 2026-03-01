defmodule RiddlrWeb.AdminController do
  use RiddlrWeb, :controller
  alias Riddlr.Authorization

  plug :require_admin

  def redirect_to_riddles(conn, _params) do
    redirect(conn, to: ~p"/admin/riddles")
  end

  defp require_admin(conn, _opts) do
    if Authorization.has_permission?(conn.assigns.current_user, :manage_riddles) do
      conn
    else
      conn
      |> put_flash(:error, "Unauthorized")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end
