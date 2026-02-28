defmodule RiddlrWeb.UserSessionHTML do
  use RiddlrWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:riddlr, Riddlr.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
