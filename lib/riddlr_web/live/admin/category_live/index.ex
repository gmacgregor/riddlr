defmodule RiddlrWeb.Admin.CategoryLive.Index do
  use RiddlrWeb, :admin_live_view
  alias Riddlr.Games
  alias RiddlrWeb.AdminAuth

  # Moderators are admins but may not manage riddles or read their answers.
  on_mount {RiddlrWeb.AdminAuth, {:require_permission, :manage_riddles}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :categories, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Manage Categories")
    |> stream(:categories, Games.list_categories(), reset: true)
    |> assign(:category, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:category, Games.new_category()) |> assign(:page_title, "New Category")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    category = Games.get_category!(id)
    socket |> assign(:category, category) |> assign(:page_title, "Edit #{category.name}")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = Games.get_category!(id)

    case Games.delete_category(socket.assigns.current_scope, category) do
      {:ok, _} ->
        {:noreply,
         socket |> stream_delete(:categories, category) |> put_flash(:info, "Category deleted")}

      {:error, :unauthorized} ->
        {:noreply, AdminAuth.unauthorized(socket)}
    end
  end

  @impl true
  def handle_info({:category_saved, category}, socket) do
    {:noreply, stream_insert(socket, :categories, category, at: 0)}
  end
end
