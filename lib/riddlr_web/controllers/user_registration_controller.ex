defmodule RiddlrWeb.UserRegistrationController do
  use RiddlrWeb, :controller

  alias Riddlr.Accounts

  plug :put_page_title, "Create account" when action in [:new, :create]
  plug :put_page_title, "Check your email" when action == :check_email

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(Accounts.new_user())
    render(conn, :new, changeset: changeset, sms_enabled?: Riddlr.SMS.enabled?())
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        conn
        |> put_session(:registered_email, user.email)
        |> redirect(to: ~p"/users/register/check-email")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, sms_enabled?: Riddlr.SMS.enabled?())
    end
  end

  @doc """
  Shows a new player where the confirmation link went after sign-up.

  The email comes from the session, not the URL, so it stays out of logs.
  With no email in the session, redirects to the sign-up page.
  """
  @spec check_email(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def check_email(conn, _params) do
    case get_session(conn, :registered_email) do
      nil -> redirect(conn, to: ~p"/users/register")
      email -> render(conn, :check_email, email: email)
    end
  end

  @doc """
  Sends the confirmation link again to the email from sign-up, then returns
  to the check-email page. `Accounts.resend_login_instructions/2` refuses a
  resend within a minute of the last link. A banned user gets no link but the
  same reply, as on the log-in page.
  """
  @spec resend(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resend(conn, _params) do
    with email when is_binary(email) <- get_session(conn, :registered_email),
         %Accounts.User{} = user <- Accounts.get_user_by_email(email) do
      case maybe_resend(user) do
        {:error, :too_soon} ->
          conn
          |> put_flash(:error, "We just sent a link. Wait a minute, then try again.")
          |> redirect(to: ~p"/users/register/check-email")

        {:ok, _email} ->
          conn
          |> put_flash(:info, "We sent another link. Please check your email again.")
          |> redirect(to: ~p"/users/register/check-email")
      end
    else
      _ -> redirect(conn, to: ~p"/users/register")
    end
  end

  @spec maybe_resend(Accounts.User.t()) :: {:ok, :not_sent} | Accounts.resend_result()
  defp maybe_resend(user) do
    if Accounts.banned?(user) do
      {:ok, :not_sent}
    else
      Accounts.resend_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
    end
  end
end
