defmodule RiddlrWeb.UserRegistrationController do
  use RiddlrWeb, :controller

  alias Riddlr.Accounts

  plug :put_page_title, "Create account"

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
        |> put_flash(
          :info,
          "An email was sent to #{user.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, sms_enabled?: Riddlr.SMS.enabled?())
    end
  end
end
