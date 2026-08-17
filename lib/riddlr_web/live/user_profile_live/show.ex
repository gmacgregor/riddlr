defmodule RiddlrWeb.UserProfileLive.Show do
  use RiddlrWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Profile")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.auth_shell title="Profile">
        <:subtitle>Your account at a glance.</:subtitle>

        <dl class="rg-auth__meta">
          <div class="rg-auth__meta-row">
            <dt class="rg-auth__meta-label">Username</dt>
            <dd class="rg-auth__meta-value">{@current_user.username}</dd>
          </div>
          <div class="rg-auth__meta-row">
            <dt class="rg-auth__meta-label">Email</dt>
            <dd class="rg-auth__meta-value">{@current_user.email}</dd>
          </div>
        </dl>

        <div class="rg-auth__footer">
          <.link navigate={~p"/users/settings"} class="rg-auth__link">Edit settings</.link>
        </div>
      </.auth_shell>
    </Layouts.app>
    """
  end
end
