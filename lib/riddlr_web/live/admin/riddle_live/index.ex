defmodule RiddlrWeb.Admin.RiddleLive.Index do
  use RiddlrWeb, :live_view
  alias Riddlr.Games
  alias Riddlr.Games.Riddle

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Manage Riddles") |> stream(:riddles, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> stream(:riddles, Games.list_riddles(), reset: true) |> assign(:riddle, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:riddle, %Riddle{}) |> assign(:page_title, "New Riddle")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    riddle = Games.get_riddle!(id)
    socket |> assign(:riddle, riddle) |> assign(:page_title, "Edit #{riddle.name}")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    riddle = Games.get_riddle!(id)
    socket |> assign(:riddle, riddle) |> assign(:page_title, riddle.name)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    riddle = Games.get_riddle!(id)
    {:ok, _} = Games.delete_riddle(riddle)
    {:noreply, socket |> stream_delete(:riddles, riddle) |> put_flash(:info, "Riddle deleted")}
  end

  @impl true
  def handle_info({:riddle_saved, riddle}, socket) do
    {:noreply, stream_insert(socket, :riddles, riddle, at: 0)}
  end
end
