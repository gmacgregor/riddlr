defmodule RiddlrWeb.Admin.PracticeRiddleLive.FormComponent do
  @moduledoc """
  The form to add or edit a practice riddle: its description and answer.
  """

  use RiddlrWeb, :admin_live_component

  alias Riddlr.Authorization
  alias Riddlr.Games

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>
      <.form
        for={@form}
        id="practice-riddle-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:description]}
          type="textarea"
          label="Riddle"
          rows="3"
          required
          placeholder="What gets wetter the more it dries?"
        />
        <.input
          field={@form[:answer]}
          type="text"
          label="Answer (20 characters at most)"
          required
          placeholder="towel"
        />
        <div class="adm-form-controls">
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.link patch={@patch} class="rg-link-btn">Cancel</.link>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{practice_riddle: practice_riddle} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, title(assigns.action))
     |> assign_form(Games.change_practice_riddle(practice_riddle))}
  end

  @impl true
  def handle_event("validate", %{"practice_riddle" => params}, socket) do
    changeset =
      socket.assigns.practice_riddle
      |> Games.change_practice_riddle(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  # on_mount checks only run at mount, so a save checks again.
  def handle_event("save", %{"practice_riddle" => params}, socket) do
    if Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
      save(socket, socket.assigns.action, params)
    else
      {:noreply, socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")}
    end
  end

  @spec save(Phoenix.LiveView.Socket.t(), :new | :edit, map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save(socket, :new, params) do
    params |> Games.create_practice_riddle() |> saved(socket, "Practice riddle created")
  end

  defp save(socket, :edit, params) do
    socket.assigns.practice_riddle
    |> Games.update_practice_riddle(params)
    |> saved(socket, "Practice riddle updated")
  end

  @spec saved(
          {:ok, Games.PracticeRiddle.t()} | {:error, Ecto.Changeset.t()},
          Phoenix.LiveView.Socket.t(),
          String.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp saved({:ok, practice_riddle}, socket, message) do
    send(self(), {:practice_riddle_saved, practice_riddle})
    {:noreply, socket |> put_flash(:info, message) |> push_patch(to: socket.assigns.patch)}
  end

  defp saved({:error, changeset}, socket, _message),
    do: {:noreply, assign_form(socket, changeset)}

  @spec assign_form(Phoenix.LiveView.Socket.t(), Ecto.Changeset.t()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @spec title(:new | :edit) :: String.t()
  defp title(:new), do: "New practice riddle"
  defp title(:edit), do: "Edit practice riddle"
end
