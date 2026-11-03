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

    # A signed-in player who is not an admin gets a 404 rather than a hint
    # that the page exists. The router has sent any guest to log in already.
    scope = socket.assigns.current_scope

    unless Authorization.admin?(scope && scope.user) do
      raise RiddlrWeb.NotFoundError
    end

    {:cont, attach_hook(socket, :current_path, :handle_params, &assign_current_path/3)}
  end

  def on_mount({:require_role, allowed_roles}, _params, session, socket) do
    socket = mount_current_user(socket, session)

    scope = socket.assigns.current_scope

    if scope && scope.user.role in allowed_roles do
      {:cont, socket}
    else
      socket = socket |> put_flash(:error, "You don't have permission.") |> redirect(to: ~p"/")
      {:halt, socket}
    end
  end

  # Narrows an admin page to the roles that hold one permission. It runs after
  # `:require_admin`, which lets every admin role in, including moderators.
  def on_mount({:require_permission, permission}, _params, _session, socket) do
    if Authorization.has_permission?(socket.assigns.current_scope.user, permission) do
      {:cont,
       attach_hook(socket, :recheck_permission, :handle_params, fn _params, _url, socket ->
         recheck_permission(socket, permission)
       end)}
    else
      socket = socket |> put_flash(:error, "You don't have permission.") |> redirect(to: ~p"/")
      {:halt, socket}
    end
  end

  @doc """
  Flashes "Unauthorized" and sends the user home. Admin events call this when
  a context write returns `{:error, :unauthorized}`.
  """
  @spec unauthorized(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def unauthorized(socket) do
    socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")
  end

  # A live_patch runs handle_params with no new mount, so without this a
  # demoted editor could still patch to a riddle and read its answers.
  @spec recheck_permission(Phoenix.LiveView.Socket.t(), atom()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  defp recheck_permission(socket, permission) do
    case Authorization.authorize(socket.assigns.current_scope, permission) do
      :ok ->
        {:cont, socket}

      {:error, :unauthorized} ->
        socket =
          socket |> put_flash(:error, "You don't have permission.") |> push_navigate(to: ~p"/")

        {:halt, socket}
    end
  end

  # The admin layout reads :current_path to mark the current nav link.
  defp assign_current_path(_params, url, socket) do
    {:cont, assign(socket, :current_path, URI.parse(url).path)}
  end

  # As in RiddlrWeb.UserAuth: the first render reuses the conn's scope, and
  # the connected mount looks the token up again.
  defp mount_current_user(socket, session) do
    assign_new(socket, :current_scope, fn ->
      session |> session_user() |> Scope.for_user()
    end)
  end

  defp session_user(%{"user_token" => token}) do
    case Accounts.get_user_by_session_token(token) do
      {user, _} -> user
      nil -> nil
    end
  end

  defp session_user(_session), do: nil
end
