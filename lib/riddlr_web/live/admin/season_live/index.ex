defmodule RiddlrWeb.Admin.SeasonLive.Index do
  @moduledoc """
  The admin seasons page: lists every season and opens the season form.
  """
  use RiddlrWeb, :admin_live_view
  alias Riddlr.Games
  alias RiddlrWeb.AdminAuth

  # Moderators are admins but may not manage riddles, and so not seasons.
  on_mount {RiddlrWeb.AdminAuth, {:require_permission, :manage_riddles}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Manage Seasons") |> stream(:seasons, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Manage Seasons")
    |> stream(:seasons, Games.list_seasons(), reset: true)
    |> assign(:season, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:season, Games.new_season()) |> assign(:page_title, "New Season")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    season = Games.get_season!(id)
    socket |> assign(:season, season) |> assign(:page_title, "Edit #{season.name}")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    season = Games.get_season!(id)

    case Games.delete_season(socket.assigns.current_scope, season) do
      {:ok, _} ->
        {:noreply,
         socket |> stream_delete(:seasons, season) |> put_flash(:info, "Season deleted")}

      {:error, :unauthorized} ->
        {:noreply, AdminAuth.unauthorized(socket)}
    end
  end

  # Badge colours borrow the play status ones: upcoming reads like scheduled,
  # current like live, past like archived.
  @spec status_class(Riddlr.Games.Season.status()) :: String.t()
  defp status_class(:upcoming), do: "adm-badge--scheduled"
  defp status_class(:current), do: "adm-badge--live"
  defp status_class(:past), do: "adm-badge--archived"
end
