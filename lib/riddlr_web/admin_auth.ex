defmodule RiddlrWeb.AdminAuth do
  @moduledoc """
  Admin authentication on_mount hooks for LiveView.
  Follows the UserAuth.ex pattern.
  """
  use RiddlrWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Riddlr.Accounts
  alias Riddlr.Accounts.Scope
  alias Riddlr.Authorization

  @spec on_mount(
          :require_admin | {:require_role, [atom()]} | {:require_permission, atom()},
          map() | :not_mounted_at_router,
          map(),
          Phoenix.LiveView.Socket.t()
        ) :: {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns[:current_user] && Authorization.is_admin?(socket.assigns.current_user) do
      {:cont, attach_hook(socket, :current_path, :handle_params, &assign_current_path/3)}
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

  # Narrows an admin page to the roles that hold one permission. It runs after
  # `:require_admin`, which lets every admin role in, including moderators.
  def on_mount({:require_permission, permission}, _params, _session, socket) do
    if Authorization.has_permission?(socket.assigns[:current_user], permission) do
      {:cont, socket}
    else
      socket = socket |> put_flash(:error, "You don't have permission.") |> redirect(to: ~p"/")
      {:halt, socket}
    end
  end

  # The admin layout reads :current_path to mark the current nav link.
  defp assign_current_path(_params, url, socket) do
    {:cont, assign(socket, :current_path, URI.parse(url).path)}
  end

  defp mount_current_user(socket, session) do
    case session do
      %{"user_token" => token} ->
        case Accounts.get_user_by_session_token(token) do
          {user, _} -> assign_current_user(socket, user)
          nil -> assign_current_user(socket, nil)
        end

      %{} ->
        assign_current_user(socket, nil)
    end
  end

  # The admin layout reads :current_scope for its account controls.
  defp assign_current_user(socket, user) do
    socket
    |> assign(:current_user, user)
    |> assign(:current_scope, Scope.for_user(user))
  end
end
