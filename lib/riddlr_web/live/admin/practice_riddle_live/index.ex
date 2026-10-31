defmodule RiddlrWeb.Admin.PracticeRiddleLive.Index do
  @moduledoc """
  The admin list of practice riddles, with new and edit forms on the same
  page.
  """

  use RiddlrWeb, :admin_live_view

  alias Riddlr.Authorization
  alias Riddlr.Games
  alias Riddlr.Games.PracticeRiddle

  # Moderators reach other admin pages but may not manage riddles.
  on_mount {RiddlrWeb.AdminAuth, {:require_permission, :manage_riddles}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Manage Practice Riddles")
     |> stream(:practice_riddles, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :index, _params) do
    socket
    |> stream(:practice_riddles, Games.list_practice_riddles(), reset: true)
    |> assign(:practice_riddle, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:practice_riddle, %PracticeRiddle{})
    |> assign(:page_title, "New practice riddle")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:practice_riddle, Games.get_practice_riddle!(id))
    |> assign(:page_title, "Edit practice riddle")
  end

  # on_mount checks only run at mount, so a delete checks again.
  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
      practice_riddle = Games.get_practice_riddle!(id)
      {:ok, _} = Games.delete_practice_riddle(practice_riddle)

      {:noreply,
       socket
       |> stream_delete(:practice_riddles, practice_riddle)
       |> put_flash(:info, "Practice riddle deleted")}
    else
      {:noreply, socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:practice_riddle_saved, practice_riddle}, socket) do
    {:noreply, stream_insert(socket, :practice_riddles, practice_riddle)}
  end
end
