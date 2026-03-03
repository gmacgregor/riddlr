defmodule RiddlrWeb.Admin.RiddleLive.Index do
  use RiddlrWeb, :live_view
  alias Riddlr.Games
  alias Riddlr.Games.Riddle
  alias Riddlr.Authorization

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to riddle state transition events from Oban workers
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:ready")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:live")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")
    end

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
    # ⚠️ Authorization check required - on_mount hooks only run at mount time
    # Event handlers must verify permissions independently
    case Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
      true ->
        riddle = Games.get_riddle!(id)
        {:ok, _} = Games.delete_riddle(riddle)

        {:noreply,
         socket |> stream_delete(:riddles, riddle) |> put_flash(:info, "Riddle deleted")}

      false ->
        {:noreply, socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:riddle_saved, riddle}, socket) do
    {:noreply, stream_insert(socket, :riddles, riddle, at: 0)}
  end

  # Handle Oban worker state transitions
  def handle_info({:riddle_ready, riddle}, socket) do
    {:noreply, stream_insert(socket, :riddles, riddle)}
  end

  def handle_info({:riddle_live, riddle}, socket) do
    {:noreply, stream_insert(socket, :riddles, riddle)}
  end

  def handle_info({:riddle_completed, riddle}, socket) do
    {:noreply, stream_insert(socket, :riddles, riddle)}
  end

  def handle_info({:riddle_archived, riddle}, socket) do
    {:noreply, stream_insert(socket, :riddles, riddle)}
  end

  defp play_status_color("closed"), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
  defp play_status_color("scheduled"), do: "bg-blue-50 text-blue-700 ring-blue-700/10"
  defp play_status_color("ready"), do: "bg-yellow-50 text-yellow-800 ring-yellow-600/20"
  defp play_status_color("live"), do: "bg-green-50 text-green-700 ring-green-600/20"
  defp play_status_color("completed"), do: "bg-purple-50 text-purple-700 ring-purple-700/10"
  defp play_status_color("archived"), do: "bg-gray-50 text-gray-500 ring-gray-500/10"
  defp play_status_color(_), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
end
