defmodule RiddlrWeb.Admin.RiddleLive.Index do
  use RiddlrWeb, :live_view
  alias Riddlr.Games
  alias Riddlr.Games.Riddle
  alias Riddlr.Authorization
  import Riddlr.Utils.Datetime

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Every admin write — create, edit, schedule, delete — arrives on one topic.
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:changed")
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
    socket |> assign(:riddle, %Riddle{}) |> assign(:page_title, "New riddle")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    riddle = Games.get_riddle!(id)
    socket |> assign(:riddle, riddle) |> assign(:page_title, "Edit riddle")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    riddle = Games.get_riddle!(id)
    socket |> assign(:riddle, riddle) |> assign(:page_title, riddle.name)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    # Authorization check required - on_mount hooks only run at mount time
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

  def handle_info({:riddle_deleted, riddle}, socket) do
    {:noreply, stream_delete(socket, :riddles, riddle)}
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

  defp format_live_date(live_date) when is_struct(live_date, DateTime) do
    live_time_display(live_date)
  end

  defp format_live_date(nil), do: nil

  defp play_status_text("closed"), do: "unscheduled"
  defp play_status_text("scheduled"), do: "scheduled"
  defp play_status_text("ready"), do: "lobby open"
  defp play_status_text("live"), do: "live"
  defp play_status_text("completed"), do: "cooldown"
  defp play_status_text("archived"), do: "archived"

  defp play_status_color("closed"), do: "adm-badge--closed"
  defp play_status_color("scheduled"), do: "adm-badge--scheduled"
  defp play_status_color("ready"), do: "adm-badge--ready"
  defp play_status_color("live"), do: "adm-badge--live"
  defp play_status_color("completed"), do: "adm-badge--completed"
  defp play_status_color("archived"), do: "adm-badge--archived"
  defp play_status_color(_), do: "adm-badge--closed"
end
