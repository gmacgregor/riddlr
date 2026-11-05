defmodule RiddlrWeb.Admin.SeasonLive.FormComponent do
  @moduledoc """
  The form to create or edit a season.
  """
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
        id="season-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={f[:name]} type="text" label="Name" required />
        <.input field={f[:description]} type="textarea" label="Description" />
        <p id="season-dates-note" class="adm-note">
          A season starts at 12:00am Eastern time on its start date and runs until 11:59pm on its end date.
        </p>
        <div class="adm-form-row">
          <.input
            field={f[:starts_on]}
            type="date"
            label="Start date"
            required
            disabled={:starts_on in @locked}
          />
          <.input
            field={f[:ends_on]}
            type="date"
            label="End date"
            required
            disabled={:ends_on in @locked}
          />
        </div>
        <p :if={@locked != []} id="season-locked-note" class="adm-note">{locked_note(@locked)}</p>
        <div class="adm-form-controls">
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.link patch={@patch} class="rg-link-btn">Cancel</.link>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{season: season} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, title(assigns.action))
     |> assign(:locked, Games.season_locked_dates(season))
     |> assign_form(Games.change_season(season))}
  end

  @impl true
  def handle_event("validate", %{"season" => params}, socket) do
    changeset =
      socket.assigns.season |> Games.change_season(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"season" => params}, socket) do
    save(socket, socket.assigns.action, params)
  end

  @spec save(Phoenix.LiveView.Socket.t(), :new | :edit, map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp save(socket, :edit, params) do
    socket.assigns.current_scope
    |> Games.update_season(socket.assigns.season, params)
    |> saved(socket, "Season updated")
  end

  defp save(socket, :new, params) do
    socket.assigns.current_scope
    |> Games.create_season(params)
    |> saved(socket, "Season created")
  end

  @spec saved(
          {:ok, Riddlr.Games.Season.t()} | {:error, Ecto.Changeset.t() | :unauthorized},
          Phoenix.LiveView.Socket.t(),
          String.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  # The index reloads its list when the patch lands back on it.
  defp saved({:ok, _season}, socket, message) do
    {:noreply, socket |> put_flash(:info, message) |> push_patch(to: socket.assigns.patch)}
  end

  defp saved({:error, %Ecto.Changeset{} = changeset}, socket, _message),
    do: {:noreply, assign_form(socket, changeset)}

  defp saved({:error, :unauthorized}, socket, _message),
    do: {:noreply, AdminAuth.unauthorized(socket)}

  @spec assign_form(Phoenix.LiveView.Socket.t(), Ecto.Changeset.t()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @spec locked_note([:starts_on | :ends_on]) :: String.t()
  defp locked_note([:starts_on, :ends_on]), do: "This season is over, so its dates are locked."
  defp locked_note([:starts_on]), do: "This season has started, so its start date is locked."

  @spec title(:new | :edit) :: String.t()
  defp title(:new), do: "New Season"
  defp title(:edit), do: "Edit Season"
end
