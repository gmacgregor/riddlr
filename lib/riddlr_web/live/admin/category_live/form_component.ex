defmodule RiddlrWeb.Admin.CategoryLive.FormComponent do
  use RiddlrWeb, :admin_live_component
  alias Riddlr.Games
  alias RiddlrWeb.AdminAuth

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
        <div class="adm-form-controls">
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.link patch={@patch} class="rg-link-btn">Cancel</.link>
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
    save(socket, socket.assigns.action, params)
  end

  defp save(socket, :edit, params) do
    socket.assigns.current_scope
    |> Games.update_category(socket.assigns.category, params)
    |> saved(socket, "Category updated")
  end

  defp save(socket, :new, params) do
    socket.assigns.current_scope
    |> Games.create_category(params)
    |> saved(socket, "Category created")
  end

  defp saved({:ok, category}, socket, message) do
    send(self(), {:category_saved, category})
    {:noreply, socket |> put_flash(:info, message) |> push_patch(to: socket.assigns.patch)}
  end

  defp saved({:error, %Ecto.Changeset{} = changeset}, socket, _message),
    do: {:noreply, assign_form(socket, changeset)}

  defp saved({:error, :unauthorized}, socket, _message),
    do: {:noreply, AdminAuth.unauthorized(socket)}

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
  defp title(:new), do: "New Category"
  defp title(:edit), do: "Edit Category"
end
