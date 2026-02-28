defmodule RiddlrWeb.AdminController do
  use RiddlrWeb, :controller

  def redirect_to_riddles(conn, _params) do
    redirect(conn, to: ~p"/admin/riddles")
  end
end
