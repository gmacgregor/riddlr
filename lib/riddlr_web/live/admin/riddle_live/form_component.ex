defmodule RiddlrWeb.Admin.RiddleLive.FormComponent do
  use RiddlrWeb, :live_component
  alias Riddlr.Games
  alias Riddlr.Games.RiddleScheduler
  alias Riddlr.Authorization

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
        <.input field={f[:description]} type="textarea" label="Description" rows="4" />
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
          field={f[:answers]}
          type="textarea"
          label="Answers (one per line, most acceptable first)"
          rows="3"
          required
          placeholder=""
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

    # Load categories for select dropdown
    categories = Games.list_categories() |> Enum.map(&{&1.name, &1.id})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, title(assigns.action))
     |> assign(:categories, categories)
     |> assign_form(Games.change_riddle(riddle))}
  end

  @impl true
  def handle_event("validate", %{"riddle" => params}, socket) do
    params = prepare_params_for_changeset(params)
    changeset = Games.change_riddle(socket.assigns.riddle, params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"riddle" => params}, socket) do
    if Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
      params = prepare_params_for_changeset(params)
      save(socket, socket.assigns.action, params)
    else
      {:noreply, socket |> put_flash(:error, "Unauthorized") |> push_navigate(to: ~p"/")}
    end
  end

  defp save(socket, :edit, params) do
    old_riddle = socket.assigns.riddle
    old_live_date = old_riddle.live_date
    new_live_date = parse_live_date(params["live_date"])

    # Auto-schedule if riddle is closed, date is future, and user didn't manually override status
    result =
      if should_auto_schedule?(old_riddle, params, new_live_date) do
        Games.schedule_riddle(old_riddle, new_live_date)
      else
        Games.update_riddle(old_riddle, params)
      end

    case result do
      {:ok, %{riddle: updated_riddle, ready_job: ready_job, live_job: live_job}} ->
        # Scheduled with jobs
        send(self(), {:riddle_saved, updated_riddle})
        ready_time = Calendar.strftime(ready_job.scheduled_at, "%Y-%m-%d %H:%M:%S UTC")
        live_time = Calendar.strftime(live_job.scheduled_at, "%Y-%m-%d %H:%M:%S UTC")

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Riddle scheduled. Will go ready at #{ready_time}, live at #{live_time}"
         )
         |> push_patch(to: socket.assigns.patch)}

      {:ok, riddle} ->
        # Check if we need to reschedule due to live_date change
        if should_reschedule?(old_riddle, riddle, old_live_date) do
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
    case Games.create_riddle(params) do
      {:ok, riddle} ->
        send(self(), {:riddle_saved, riddle})

        {:noreply,
         socket |> put_flash(:info, "Riddle created") |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Auto-schedule only if:
  # - Riddle is (or will be) published
  # - Riddle is currently closed
  # - Live date is set and in the future
  # - User hasn't manually selected an incompatible play_status
  defp should_auto_schedule?(_riddle, _params, nil), do: false

  defp should_auto_schedule?(riddle, params, live_date) do
    # Check if riddle is or will be published
    publish_status = Map.get(params, "publish_status", riddle.publish_status)

    publish_status == "published" &&
      riddle.play_status == "closed" &&
      DateTime.compare(live_date, DateTime.utc_now()) != :lt &&
      params["play_status"] in ["closed", "scheduled"]
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

  defp parse_live_date(nil), do: nil
  defp parse_live_date(""), do: nil

  defp parse_live_date(datetime_string) when is_binary(datetime_string) do
    case NaiveDateTime.from_iso8601(datetime_string) do
      {:ok, naive_datetime} ->
        DateTime.from_naive!(naive_datetime, "Etc/UTC")

      _ ->
        nil
    end
  end

  defp parse_live_date(_), do: nil

  defp assign_form(socket, changeset) do
    # Convert answers array back to string for display in form
    changeset =
      case Ecto.Changeset.get_field(changeset, :answers) do
        nil ->
          changeset

        [] ->
          changeset

        answers when is_list(answers) ->
          Ecto.Changeset.put_change(changeset, :answers, Enum.join(answers, "\n"))

        _ ->
          changeset
      end

    assign(socket, :form, to_form(changeset))
  end

  defp title(:new), do: "New Riddle"
  defp title(:edit), do: "Edit Riddle"

  # Convert riddle's answers array to newline-separated string for textarea
  defp prepare_riddle_for_form(riddle) do
    case riddle.answers do
      nil ->
        riddle

      [] ->
        riddle

      answers when is_list(answers) ->
        Map.put(riddle, :answers, Enum.join(answers, "\n"))

      _ ->
        riddle
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
