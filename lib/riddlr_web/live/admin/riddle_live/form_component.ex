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
      <%!-- <.header>{@title}</.header> --%>
      <p>
        Play status
        <span class={["adm-badge", play_status_color(@riddle.play_status)]}>
          {@riddle.play_status}
        </span>
      </p>
      <.form
        :let={f}
        class="form"
        for={@form}
        id="riddle-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={f[:name]}
          type="text"
          label="Name"
          required
          placeholder="…"
        />
        <div class="adm-form-row adm-form-row--2-1-1-1">
          <div>
            <.input
              field={f[:category_id]}
              type="select"
              label="Category"
              prompt="Choose a category"
              options={@categories}
              required
            />
          </div>
          <div>
            <.input
              field={f[:difficulty]}
              type="select"
              label="Difficulty"
              prompt="Choose"
              options={Riddlr.Games.Riddle.difficulties()}
            />
          </div>
          <div>
            <.input
              field={f[:solve_time]}
              type="number"
              label="Solve time (sec)"
              min="1"
              required
              placeholder={solve_time()}
            />
          </div>
          <div>
            <.input
              field={f[:hint_delay]}
              type="number"
              label="Hint delay (sec)"
              min="0"
              placeholder={hint_delay()}
            />
          </div>
        </div>
        <.input
          field={f[:description]}
          type="textarea"
          label="Riddle"
          rows="4"
          required
          placeholder="What disappears as soon as you say its name?"
        />
        <.input
          field={f[:answers]}
          type="textarea"
          label="Answers (one per line, most acceptable first)"
          rows="3"
          required
          placeholder="silence"
        />
        <.input field={f[:hint]} type="text" label="Hint" rows="2" placeholder="Optional hint…" />
        <div class="adm-form-row adm-form-row--equal">
          <div>
            <.input
              field={f[:ready_before_seconds]}
              type="number"
              label="Lobby opens (sec before live)"
              min="1"
            />
          </div>
          <div>
            <.input
              field={f[:archive_after_seconds]}
              type="number"
              label="Archive cool off (sec)"
              min="0"
            />
          </div>
          <div>
            <.input
              field={f[:publish_status]}
              type="select"
              label="Publish status"
              options={Riddlr.Games.Riddle.publish_statuses()}
            />
          </div>
          <div>
            <.input
              field={f[:live_date]}
              type="datetime-local"
              label="Live date (EST/EDT)"
            />
          </div>
        </div>
        <div class="adm-form-controls">
          <.button phx-disable-with="Saving...">Save</.button>
          <.link patch={@patch}>
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

    # Pre-select "logic" category for new riddles
    riddle =
      if assigns.action == :new && is_nil(riddle.category_id) do
        logic_id = Enum.find_value(categories, fn {name, id} -> name == "logic" && id end)
        %{riddle | category_id: logic_id}
      else
        riddle
      end

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
        Games.schedule_riddle(current_riddle, effective_live_date, params)
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
           "Riddle scheduled. The lobby will open #{ready_time}, and the game will be live #{live_time}"
         )
         |> push_patch(to: socket.assigns.patch)}

      {:ok, riddle} ->
        # Check if we need to reschedule due to live_date change
        if should_reschedule?(current_riddle, riddle, old_live_date) do
          RiddleScheduler.reschedule_jobs(riddle, riddle.live_date)
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
    effective_live_date = params["live_date"]

    with {:ok, riddle} <- Games.create_riddle(params) do
      if should_auto_schedule?(riddle, params, effective_live_date) do
        case Games.schedule_riddle(riddle, effective_live_date) do
          {:ok, %{riddle: scheduled_riddle}} ->
            send(self(), {:riddle_saved, scheduled_riddle})

            {:noreply,
             socket
             |> put_flash(
               :info,
               "Riddle: \"#{riddle.name}\" saved."
             )
             |> push_patch(to: socket.assigns.patch)}

          {:error, _reason} ->
            send(self(), {:riddle_saved, riddle})

            {:noreply,
             socket
             |> put_flash(:warning, "Riddle created but scheduling failed.")
             |> push_patch(to: socket.assigns.patch)}
        end
      else
        send(self(), {:riddle_saved, riddle})

        {:noreply,
         socket |> put_flash(:info, "Riddle created") |> push_patch(to: socket.assigns.patch)}
      end
    else
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
  # - live_date changed OR (status is scheduled and ready_before_seconds changed)
  # - new live_date is not nil
  defp should_reschedule?(old_riddle, new_riddle, old_live_date) do
    new_riddle.publish_status == "published" and
      new_riddle.play_status in ["scheduled", "ready"] and
      not is_nil(new_riddle.live_date) and
      (old_live_date != new_riddle.live_date or
         (new_riddle.play_status == "scheduled" and
            old_riddle.ready_before_seconds != new_riddle.ready_before_seconds))
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

  defp play_status_color("closed"), do: "adm-badge--closed"
  defp play_status_color("scheduled"), do: "adm-badge--scheduled"
  defp play_status_color("ready"), do: "adm-badge--ready"
  defp play_status_color("live"), do: "adm-badge--live"
  defp play_status_color("completed"), do: "adm-badge--completed"
  defp play_status_color("archived"), do: "adm-badge--archived"
  defp play_status_color(_), do: "adm-badge--closed"
end
