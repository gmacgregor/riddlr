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
          min="1"
          required
        />
        <.input field={f[:hint]} type="textarea" label="Hint" rows="2" />
        <.input field={f[:hint_delay]} type="number" label="Hint Delay (seconds)" min="0" />
        <.input
          field={f[:answers]}
          type="textarea"
          label="Answers (one per line)"
          rows="3"
          required
          placeholder="keyboard&#10;a keyboard&#10;computer keyboard"
        />
        <.input
          field={f[:publish_status]}
          type="select"
          label="Publish Status"
          options={Riddlr.Games.Riddle.publish_statuses()}
        />
        <.input
          field={f[:play_status]}
          type="select"
          label="Play Status"
          options={Riddlr.Games.Riddle.play_statuses()}
        />
        <.input
          field={f[:live_date]}
          type="datetime-local"
          label="Live Date (when riddle goes live)"
        />
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
    # Convert answers array to newline-separated string for textarea
    riddle = prepare_riddle_for_form(riddle)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, title(assigns.action))
     |> assign_form(Games.change_riddle(riddle))}
  end

  @impl true
  def handle_event("validate", %{"riddle" => params}, socket) do
    params = prepare_params_for_changeset(params)
    changeset = Games.change_riddle(socket.assigns.riddle, params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"riddle" => params}, socket) do
    params = prepare_params_for_changeset(params)
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

  defp assign_form(socket, changeset) do
    # Convert answers array back to string for display in form
    changeset =
      case Ecto.Changeset.get_field(changeset, :answers) do
        nil -> changeset
        [] -> changeset
        answers when is_list(answers) ->
          Ecto.Changeset.put_change(changeset, :answers, Enum.join(answers, "\n"))
        _ -> changeset
      end

    assign(socket, :form, to_form(changeset))
  end

  defp title(:new), do: "New Riddle"
  defp title(:edit), do: "Edit Riddle"

  # Convert riddle's answers array to newline-separated string for textarea
  defp prepare_riddle_for_form(riddle) do
    case riddle.answers do
      nil -> riddle
      [] -> riddle
      answers when is_list(answers) ->
        Map.put(riddle, :answers, Enum.join(answers, "\n"))
      _ -> riddle
    end
  end

  # Convert textarea string to array of answers
  defp prepare_params_for_changeset(params) do
    case Map.get(params, "answers") do
      nil ->
        params
      "" ->
        Map.put(params, "answers", [])
      answers_string when is_binary(answers_string) ->
        answers =
          answers_string
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
        Map.put(params, "answers", answers)
      _ ->
        params
    end
  end
end
