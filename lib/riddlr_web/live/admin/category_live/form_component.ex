defmodule RiddlrWeb.Admin.CategoryLive.FormComponent do
  use RiddlrWeb, :live_component
  alias Riddlr.Games
  alias Riddlr.Authorization

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>
      <.form
        :let={f}
        for={@form}
        id="category-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={f[:name]} type="text" label="Name" required />
        <div class="mt-4 flex gap-2">
          <.button phx-disable-with="Saving...">Save</.button>
          <.link patch={@patch} class="btn">
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{category: category} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, title(assigns.action))
     |> assign_form(Games.change_category(category))}
  end

  @impl true
  def handle_event("validate", %{"category" => params}, socket) do
    changeset =
      Games.change_category(socket.assigns.category, params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"category" => params}, socket) do
    if Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
      save(socket, socket.assigns.action, params)
    else
      {:noreply, socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")}
    end
  end

  defp save(socket, :edit, params) do
    case Games.update_category(socket.assigns.category, params) do
      {:ok, category} ->
        send(self(), {:category_saved, category})

        {:noreply,
         socket |> put_flash(:info, "Category updated") |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :new, params) do
    case Games.create_category(params) do
      {:ok, category} ->
        send(self(), {:category_saved, category})

        {:noreply,
         socket |> put_flash(:info, "Category created") |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
  defp title(:new), do: "New Category"
  defp title(:edit), do: "Edit Category"
end
