defmodule RiddlrWeb.AdminAuth do
  @moduledoc """
  Admin authentication on_mount hooks for LiveView.
  Follows the UserAuth.ex pattern.
  """
  use RiddlrWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Riddlr.Accounts
  alias Riddlr.Authorization

  def on_mount(:require_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns[:current_user] && Authorization.is_admin?(socket.assigns.current_user) do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You must be an admin to access this page.")
        |> redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  def on_mount({:require_role, allowed_roles}, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns[:current_user] && socket.assigns.current_user.role in allowed_roles do
      {:cont, socket}
    else
      socket = socket |> put_flash(:error, "You don't have permission.") |> redirect(to: ~p"/")
      {:halt, socket}
    end
  end

  defp mount_current_user(socket, session) do
    case session do
      %{"user_token" => token} ->
        case Accounts.get_user_by_session_token(token) do
          {user, _} -> assign(socket, :current_user, user)
          nil -> assign(socket, :current_user, nil)
        end

      %{} ->
        assign(socket, :current_user, nil)
    end
  end
end
