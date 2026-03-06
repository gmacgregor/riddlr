defmodule RiddlrWeb.Admin.RiddleLive.FormComponent do
  use RiddlrWeb, :live_component
  alias Riddlr.Games
  alias Riddlr.Games.RiddleScheduler
  alias Riddlr.Authorization
  import Riddlr.Utils.Datetime

  defp hint_delay() do
    Riddlr.Games.Riddle.default_hint_delay()
  end

  defp solve_time() do
    Riddlr.Games.Riddle.default_solve_time()
  end

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
        <.input
          field={f[:category_id]}
          type="select"
          label="Category"
          prompt="Choose a category"
          options={@categories}
          required
        />
        <.input
          field={f[:difficulty]}
          type="select"
          label="Difficulty"
          prompt="Choose"
          options={Riddlr.Games.Riddle.difficulties()}
        />
        <.input field={f[:description]} type="textarea" label="Riddle" rows="4" required />
        <.input
          field={f[:answers]}
          type="textarea"
          label="Answers (one per line, most acceptable first)"
          rows="3"
          required
          placeholder=""
        />
        <.input
          field={f[:solve_time]}
          type="number"
          label="Solve Time (seconds)"
          min="1"
          required
          placeholder={solve_time()}
        />
        <.input field={f[:hint]} type="textarea" label="Hint" rows="2" />
        <.input
          field={f[:hint_delay]}
          type="number"
          label="Hint Delay (seconds)"
          min="0"
          placeholder={hint_delay()}
        />
        <.input
          field={f[:publish_status]}
          type="select"
          label="Publish Status"
          options={Riddlr.Games.Riddle.publish_statuses()}
        />
        <div class="space-y-2">
          <label class="block text-sm font-medium leading-6 text-gray-900">
            Play Status
          </label>
          <div>
            <span class={[
              "inline-flex items-center rounded-md px-2 py-1 text-sm font-medium ring-1 ring-inset",
              play_status_color(@riddle.play_status)
            ]}>
              {@riddle.play_status}
            </span>
            <p class="mt-2 text-sm text-gray-500">
              Play status is managed automatically by the system based on publish status and scheduling.
            </p>
          </div>
        </div>
        <%= if @riddle.play_status in ["completed", "archived"] do %>
          <div class="space-y-2">
            <.input
              field={f[:archive_cooldown_minutes]}
              type="number"
              label="Archive Cooldown (minutes)"
              min="0"
            />
            <p class="text-sm text-gray-500">
              Minutes to wait before archiving after completion. Set to 0 to skip cooldown.
            </p>
          </div>
        <% end %>
        <.input
          field={f[:live_date]}
          type="datetime-local"
          label="Live Date (EST/EDT - when riddle goes live)"
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
    # Load categories for select dropdown
    categories = Games.list_categories() |> Enum.map(&{&1.name, &1.id})

    changeset = Games.change_riddle(riddle)
    form_title = title(assigns.action)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, form_title)
     |> assign(:categories, categories)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"riddle" => params}, socket) do
    params = prepare_params_for_changeset(params)
    # Convert live_date to UTC before validation to prevent Ecto from treating it as UTC
    params = convert_live_date_param(params)
    changeset = Games.change_riddle(socket.assigns.riddle, params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"riddle" => params}, socket) do
    if Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
      params = prepare_params_for_changeset(params)
      params = convert_live_date_param(params)
      save(socket, socket.assigns.action, params)
    else
      {:noreply, socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")}
    end
  end

  defp save(socket, :edit, params) do
    current_riddle = socket.assigns.riddle
    old_live_date = current_riddle.live_date
    # live_date already converted by convert_live_date_param
    effective_live_date = params["live_date"] || current_riddle.live_date

    result =
      if should_auto_schedule?(current_riddle, params, effective_live_date) do
        Games.schedule_riddle(current_riddle, effective_live_date)
      else
        Games.update_riddle(current_riddle, params)
      end

    case result do
      {:ok, %{riddle: updated_riddle, ready_job: ready_job, live_job: live_job}} ->
        # Scheduled with jobs
        send(self(), {:riddle_saved, updated_riddle})
        ready_time_est = to_est_datetime(ready_job.scheduled_at)
        live_time_est = to_est_datetime(live_job.scheduled_at)
        ready_time = ready_time_display(ready_time_est)
        live_time = live_time_display(live_time_est)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Riddle scheduled. Will go ready at #{ready_time}, live at #{live_time}"
         )
         |> push_patch(to: socket.assigns.patch)}

      {:ok, riddle} ->
        # Check if we need to reschedule due to live_date change
        if should_reschedule?(current_riddle, riddle, old_live_date) do
          RiddleScheduler.reschedule_jobs(riddle.id, riddle.live_date)
        end

        # Regular update
        send(self(), {:riddle_saved, riddle})

        {:noreply,
         socket |> put_flash(:info, "Riddle updated") |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :new, params) do
    # live_date already converted by convert_live_date_param
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
    changeset =
      changeset
      |> convert_answers_for_form()
      |> convert_live_date_for_form()

    assign(socket, :form, to_form(changeset))
  end

  defp convert_answers_for_form(changeset) do
    case Ecto.Changeset.get_field(changeset, :answers) do
      answers when is_list(answers) and answers != [] ->
        Ecto.Changeset.put_change(changeset, :answers, Enum.join(answers, "\n"))

      _ ->
        changeset
    end
  end

  defp convert_live_date_for_form(changeset) do
    # Convert UTC datetime to EST for datetime-local input display
    case Ecto.Changeset.get_field(changeset, :live_date) do
      %DateTime{} = live_date ->
        local_string = to_local_input(live_date)
        Ecto.Changeset.put_change(changeset, :live_date, local_string)

      _ ->
        changeset
    end
  end

  # Auto-schedule only if:
  # - Riddle is (or will be) published
  # - Riddle is currently closed
  # - Live date is set and in the future
  defp should_auto_schedule?(_riddle, _params, nil), do: false

  defp should_auto_schedule?(riddle, params, live_date) do
    # Check if riddle is or will be published
    publish_status = Map.get(params, "publish_status", riddle.publish_status)

    riddle.play_status == "closed" &&
      publish_status == "published" &&
      DateTime.compare(live_date, DateTime.utc_now()) != :lt
  end

  # Reschedule jobs if:
  # - Riddle is published
  # - Play status is scheduled or ready (jobs are pending)
  # - live_date actually changed
  # - new live_date is not nil
  defp should_reschedule?(_old_riddle, new_riddle, old_live_date) do
    new_riddle.publish_status == "published" and
      new_riddle.play_status in ["scheduled", "ready"] and
      old_live_date != new_riddle.live_date and
      not is_nil(new_riddle.live_date)
  end

  defp title(:new), do: "New Riddle"
  defp title(:edit), do: "Edit Riddle"

  # Convert live_date from EST/EDT to UTC
  defp convert_live_date_param(params) do
    case params["live_date"] do
      nil ->
        params

      "" ->
        Map.delete(params, "live_date")

      datetime_string when is_binary(datetime_string) ->
        case to_utc_datetime(datetime_string) do
          nil -> Map.delete(params, "live_date")
          utc_datetime -> Map.put(params, "live_date", utc_datetime)
        end

      # Already a DateTime (shouldn't happen but handle it)
      %DateTime{} ->
        params

      _ ->
        Map.delete(params, "live_date")
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

  # Helper function to assign color classes based on play_status
  defp play_status_color("closed"), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
  defp play_status_color("scheduled"), do: "bg-blue-50 text-blue-700 ring-blue-700/10"
  defp play_status_color("ready"), do: "bg-yellow-50 text-yellow-800 ring-yellow-600/20"
  defp play_status_color("live"), do: "bg-green-50 text-green-700 ring-green-600/20"
  defp play_status_color("completed"), do: "bg-purple-50 text-purple-700 ring-purple-700/10"
  defp play_status_color("archived"), do: "bg-gray-50 text-gray-500 ring-gray-500/10"
  defp play_status_color(_), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
end
