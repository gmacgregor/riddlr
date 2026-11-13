defmodule RiddlrWeb.Admin.PracticeRiddleLive.Index do
  @moduledoc """
  The admin list of practice riddles, with new and edit forms on the same
  page.
  """

  use RiddlrWeb, :admin_live_view

  alias Riddlr.Games
  alias RiddlrWeb.AdminAuth

  # Moderators are admins but may not manage riddles or read their answers.
  on_mount {RiddlrWeb.AdminAuth, {:require_permission, :manage_riddles}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :practice_riddles, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Manage Practice Riddles")
    |> stream(:practice_riddles, Games.list_practice_riddles(), reset: true)
    |> assign(:practice_riddle, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:practice_riddle, Games.new_practice_riddle())
    |> assign(:page_title, "New practice riddle")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:practice_riddle, Games.get_practice_riddle!(id))
    |> assign(:page_title, "Edit practice riddle")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    practice_riddle = Games.get_practice_riddle!(id)

    case Games.delete_practice_riddle(socket.assigns.current_scope, practice_riddle) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:practice_riddles, practice_riddle)
         |> put_flash(:info, "Practice riddle deleted")}

      {:error, :unauthorized} ->
        {:noreply, AdminAuth.unauthorized(socket)}
    end
  end

  @impl true
  def handle_info({:practice_riddle_saved, practice_riddle}, socket) do
    {:noreply, stream_insert(socket, :practice_riddles, practice_riddle)}
  end
end
