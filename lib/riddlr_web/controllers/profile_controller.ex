defmodule RiddlrWeb.ProfileController do
  @moduledoc """
  The signed-in player's own account page: who they are, plus the forms that
  change their account. Only changing a log-in credential needs a recent log-in.
  """
  use RiddlrWeb, :controller

  alias Riddlr.Accounts
  alias RiddlrWeb.UserAuth

  @sudo_actions ~w(update_email update_password)

  plug :require_sudo_for_credentials when action == :update
  plug :assign_changesets

  @doc "Renders the current user's profile and account forms."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    render(conn, :show)
  end

  @doc """
  Saves one profile form. The hidden `action` param names the form:
  `update_email`, `update_password` or `update_notifications`.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/profile/confirm-email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/profile")

      changeset ->
        render(conn, :show, email_changeset: %{changeset | action: :insert})
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {user, _}} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, ~p"/profile")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :show, password_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_notifications"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_notifications(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Notification settings saved.")
        |> redirect(to: ~p"/profile")

      {:error, changeset} ->
        render(conn, :show, notifications_changeset: changeset)
    end
  end

  def update(conn, _params) do
    conn
    |> put_flash(:error, "Unknown form.")
    |> redirect(to: ~p"/profile")
  end

  @doc "Applies an email change from the link sent to the new address."
  @spec confirm_email(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/profile")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/profile")
    end
  end

  @spec require_sudo_for_credentials(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp require_sudo_for_credentials(%{params: %{"action" => action}} = conn, opts)
       when action in @sudo_actions do
    UserAuth.require_sudo_mode(conn, opts)
  end

  defp require_sudo_for_credentials(conn, _opts), do: conn

  @spec assign_changesets(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp assign_changesets(conn, _opts) do
    user = conn.assigns.current_scope.user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
    |> assign(:notifications_changeset, Accounts.change_user_notifications(user))
  end
end
