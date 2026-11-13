defmodule RiddlrWeb.Admin.RiddleLive.Index do
  use RiddlrWeb, :admin_live_view
  alias Riddlr.Games
  alias RiddlrWeb.AdminAuth
  import RiddlrWeb.AdminTime

  # Moderators are admins but may not manage riddles or read their answers.
  on_mount {RiddlrWeb.AdminAuth, {:require_permission, :manage_riddles}}

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

    {:ok,
     socket
     |> assign(:status, "published")
     |> assign(:counts, nil)
     |> stream(:riddles, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # The list loads once the socket connects, so the first render runs no
  # query for it. Each tab shows at most 100 riddles of one publish status.
  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, "Manage Riddles")
    |> assign(:status, tab_status(params["status"]))
    |> assign(:riddle, nil)
    |> load_riddles()
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:riddle, Games.new_riddle()) |> assign(:page_title, "New riddle")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    riddle = Games.get_riddle!(id)
    socket |> assign(:riddle, riddle) |> assign(:page_title, "Edit riddle")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    riddle = Games.get_riddle!(id)

    case Games.delete_riddle(socket.assigns.current_scope, riddle) do
      {:ok, _} ->
        {:noreply,
         socket |> stream_delete(:riddles, riddle) |> put_flash(:info, "Riddle deleted")}

      {:error, :unauthorized} ->
        {:noreply, AdminAuth.unauthorized(socket)}
    end
  end

  # Any change can move a riddle to the other tab, change its place in the
  # sort, or bring a riddle past the limit into view, so reload the tab
  # rather than touch the one riddle.
  @impl true
  def handle_info({event, _riddle}, socket)
      when event in [
             :riddle_saved,
             :riddle_deleted,
             :riddle_ready,
             :riddle_live,
             :riddle_completed,
             :riddle_archived
           ] do
    {:noreply, load_riddles(socket)}
  end

  @spec load_riddles(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_riddles(socket) do
    if connected?(socket) do
      socket
      |> stream(:riddles, Games.list_riddles(socket.assigns.status), reset: true)
      |> assign(:counts, Games.count_riddles_by_status())
    else
      stream(socket, :riddles, [], reset: true)
    end
  end

  @spec tab_status(String.t() | nil) :: String.t()
  defp tab_status("draft"), do: "draft"
  defp tab_status(_), do: "published"

  @spec index_path(String.t()) :: String.t()
  defp index_path(status), do: ~p"/admin/riddles?#{[status: status]}"

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
