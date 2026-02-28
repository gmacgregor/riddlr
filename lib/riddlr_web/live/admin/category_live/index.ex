defmodule RiddlrWeb.Admin.CategoryLive.Index do
  use RiddlrWeb, :live_view
  alias Riddlr.Games
  alias Riddlr.Games.Category
  alias Riddlr.Authorization

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Manage Categories") |> stream(:categories, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> stream(:categories, Games.list_categories(), reset: true) |> assign(:category, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:category, %Category{}) |> assign(:page_title, "New Category")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    category = Games.get_category!(id)
    socket |> assign(:category, category) |> assign(:page_title, "Edit #{category.name}")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    # Authorization check - on_mount hooks only run at mount time
    if Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
      category = Games.get_category!(id)
      {:ok, _} = Games.delete_category(category)
      {:noreply, socket |> stream_delete(:categories, category) |> put_flash(:info, "Category deleted")}
    else
      {:noreply, socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:category_saved, category}, socket) do
    {:noreply, stream_insert(socket, :categories, category, at: 0)}
  end
end
