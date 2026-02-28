defmodule RiddlrWeb.Admin.RiddleLive.FormComponent do
  use RiddlrWeb, :live_component
  alias Riddlr.Games

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>
      <.form
        :let={f}
        for={@form}
        id="riddle-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={f[:name]} type="text" label="Name" required />
        <.input field={f[:description]} type="textarea" label="Description" rows="4" required />
        <.input field={f[:category]} type="text" label="Category" />
        <.input
          field={f[:difficulty]}
          type="select"
          label="Difficulty"
          prompt="Choose"
          options={Riddlr.Games.Riddle.difficulties()}
        />
        <.input
          field={f[:solve_time]}
          type="number"
          label="Solve Time (seconds)"
          min="10"
          step="10"
          required
        />
        <.input field={f[:hint]} type="textarea" label="Hint" rows="2" />
        <.input field={f[:hint_delay]} type="number" label="Hint Delay (seconds)" min="0" />
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
  def update(%{riddle: riddle} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, title(assigns.action))
     |> assign_form(Games.change_riddle(riddle))}
  end

  @impl true
  def handle_event("validate", %{"riddle" => params}, socket) do
    changeset = Games.change_riddle(socket.assigns.riddle, params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"riddle" => params}, socket) do
    save(socket, socket.assigns.action, params)
  end

  defp save(socket, :edit, params) do
    case Games.update_riddle(socket.assigns.riddle, params) do
      {:ok, riddle} ->
        send(self(), {:riddle_saved, riddle})

        {:noreply,
         socket |> put_flash(:info, "Riddle updated") |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :new, params) do
    case Games.create_riddle(params) do
      {:ok, riddle} ->
        send(self(), {:riddle_saved, riddle})

        {:noreply,
         socket |> put_flash(:info, "Riddle created") |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
  defp title(:new), do: "New Riddle"
  defp title(:edit), do: "Edit Riddle"
end
