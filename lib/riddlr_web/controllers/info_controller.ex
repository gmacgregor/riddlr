defmodule RiddlrWeb.InfoController do
  @moduledoc """
  The info page: who runs Kriddle, how to reach us, what texts we send and
  how to stop them, and what we keep. Texts, emails and the text consent copy
  link here, so it needs no login.
  """
  use RiddlrWeb, :controller

  @doc "Shows the info page."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    {_name, contact} = Application.fetch_env!(:riddlr, :mail_from)
    render(conn, :show, page_title: "Info", contact: contact)
  end
end
