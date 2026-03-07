defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — full implementation in Phase 9.
  """

  use RiddlrWeb, :live_view

  @impl true
  def mount(%{"id" => _id}, _session, socket) do
    {:ok, assign(socket, :page_title, "Play")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-12 text-center">
      <p class="text-gray-500">Game in progress — coming in Phase 9.</p>
    </div>
    """
  end
end
