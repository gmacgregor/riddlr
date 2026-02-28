defmodule RiddlrWeb.UserProfileLive.Show do
  use RiddlrWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Profile")}
  end

  def render(assigns) do
    ~H"""
    <.header>
      Profile
      <:subtitle>Manage your account profile and settings</:subtitle>
    </.header>

    <div class="mt-8 space-y-6">
      <div class="bg-white shadow sm:rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
            <div>
              <dt class="text-sm font-medium text-gray-500">Username</dt>
              <dd class="mt-1 text-sm text-gray-900"><%= @current_user.username %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Email</dt>
              <dd class="mt-1 text-sm text-gray-900"><%= @current_user.email %></dd>
            </div>
          </dl>
        </div>
      </div>

      <div class="flex gap-4">
        <.link navigate={~p"/users/settings"} class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700">
          Edit Settings <span aria-hidden="true">→</span>
        </.link>
      </div>
    </div>
    """
  end
end
