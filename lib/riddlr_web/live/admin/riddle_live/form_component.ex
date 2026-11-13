defmodule RiddlrWeb.Admin.RiddleLive.FormComponent do
  use RiddlrWeb, :admin_live_component
  alias Riddlr.Games
  alias Riddlr.Games.Riddle
  alias Riddlr.Games.Season
  alias RiddlrWeb.AdminAuth
  import RiddlrWeb.AdminTime

  defp hint_delay() do
    Games.default_hint_delay()
  end

  defp solve_time() do
    Games.default_solve_time()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p>
        Play status
        <span class={["adm-badge", play_status_color(@riddle.play_status)]}>
          {@riddle.play_status}
        </span>
      </p>
      <.form
        :let={f}
        for={@form}
        id="riddle-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="adm-name-row">
          <div>
            <.input
              field={f[:name]}
              type="text"
              label="Name"
              required
              placeholder="…"
            />
          </div>
          <.button
            type="button"
            id="generate-riddle-name"
            phx-click="generate_name"
            phx-target={@myself}
          >
            🎲 New name
          </.button>
        </div>
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
              options={Games.riddle_difficulties()}
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
              label="Lobby open (sec)"
              min="1"
            />
          </div>
          <div>
            <.input
              field={f[:archive_after_seconds]}
              type="number"
              label="Post game chat (sec)"
              min="0"
            />
          </div>
          <div>
            <.input
              field={f[:publish_status]}
              type="select"
              label="Publish status"
              options={Games.riddle_publish_statuses()}
            />
          </div>
          <div>
            <.input
              field={f[:live_date]}
              type="datetime-local"
              label="Live date (EST/EDT)"
            />
          </div>
          <div id="riddle-season-field">
            <.season_field field={f[:season_id]} season={@season} />
          </div>
        </div>
        <div class="adm-form-controls">
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.link patch={@patch} class="rg-link-btn">Cancel</.link>
        </div>
      </.form>
    </div>
    """
  end

  # A riddle in a past season keeps it, so the season shows as text. With no
  # current or upcoming season there is nothing to pick, so the editor is sent
  # to make one. Otherwise the editor picks from the current and upcoming
  # seasons, with no blank option.
  attr :field, Phoenix.HTML.FormField, required: true
  attr :season, :any, required: true, doc: "a `season_choice()`, from `season_choice/2`"

  defp season_field(%{season: {:past, season}} = assigns) do
    assigns = assign(assigns, :season, season)

    ~H"""
    <div class="rg-field">
      <span class="rg-field__label">Season</span>
      <p id="riddle-season-past">{@season.name} (past)</p>
    </div>
    """
  end

  defp season_field(%{season: :none} = assigns) do
    ~H"""
    <div class="rg-field">
      <span class="rg-field__label">Season</span>
      <p id="riddle-season-missing" class="adm-note">
        No current or upcoming season.
        <.link navigate={~p"/admin/seasons"} class="adm-link">Create a season first</.link>
      </p>
    </div>
    """
  end

  defp season_field(%{season: {:pick, options}} = assigns) do
    assigns = assign(assigns, :options, options)

    ~H"""
    <.input field={@field} type="select" label="Season" options={@options} required />
    """
  end

  @impl true
  def update(%{riddle: riddle} = assigns, socket) do
    # Load categories for select dropdown
    categories = Games.list_categories() |> Enum.map(&{&1.name, &1.id})

    # Pre-select "logic" category and fill in a name for new riddles
    riddle =
      if assigns.action == :new && is_nil(riddle.category_id) do
        logic_id = Enum.find_value(categories, fn {name, id} -> name == "logic" && id end)
        %{riddle | category_id: logic_id}
      else
        riddle
      end

    riddle =
      if assigns.action == :new && is_nil(riddle.name) do
        %{riddle | name: Games.generate_riddle_name()}
      else
        riddle
      end

    seasons = Games.list_current_and_upcoming_seasons()

    riddle =
      if assigns.action == :new && is_nil(riddle.season_id) do
        default = Games.default_season(seasons, riddle.live_date)
        %{riddle | season_id: default && default.id}
      else
        riddle
      end

    changeset = Games.change_riddle(riddle)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:riddle, riddle)
     |> assign(:categories, categories)
     |> assign(:seasons, seasons)
     |> assign(:season, season_choice(riddle, seasons))
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"riddle" => params} = event, socket) do
    params = prepare_params_for_changeset(params)
    # Convert live_date to UTC before validation to prevent Ecto from treating it as UTC
    params = convert_live_date_param(params)
    params = follow_live_date(params, event["_target"], socket.assigns)
    changeset = Games.change_riddle(socket.assigns.riddle, params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("generate_name", _params, socket) do
    # Start from the form's current params so a new name does not wipe what
    # the editor has typed in the other fields.
    %{params: params, source: source} = socket.assigns.form
    params = Map.put(params, "name", Games.generate_riddle_name())

    changeset =
      socket.assigns.riddle
      |> Games.change_riddle(params)
      |> Map.put(:action, source.action)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"riddle" => params}, socket) do
    params = prepare_params_for_changeset(params)
    params = convert_live_date_param(params)
    save(socket, socket.assigns.action, params)
  end

  defp save(socket, action, params) do
    case Games.save_riddle(socket.assigns.current_scope, socket.assigns.riddle, params) do
      {:ok, riddle} ->
        {:noreply,
         socket
         |> put_flash(:info, saved_message(riddle, action) <> moved_message(riddle, params))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, keep_sent_season(changeset, params))}

      {:error, :unauthorized} ->
        {:noreply, AdminAuth.unauthorized(socket)}
    end
  end

  # `save_riddle/3` decides whether a save is also a schedule; the flash just
  # reports what came back.
  defp saved_message(%{play_status: "scheduled"} = riddle, _action) do
    ready_at = DateTime.add(riddle.live_date, -riddle.ready_before_seconds, :second)

    "Riddle scheduled. The lobby will open #{ready_time_display(to_est_datetime(ready_at))}, " <>
      "and the game will be live #{live_time_display(to_est_datetime(riddle.live_date))}"
  end

  defp saved_message(_riddle, :new), do: "Riddle created"
  defp saved_message(_riddle, :edit), do: "Riddle updated"

  # The save keeps a Season the editor sent unless the Live date moved into
  # another one, so a saved Season that differs from the one sent followed
  # the Live date. A riddle in a past Season sends none.
  @spec moved_message(Riddle.t(), map()) :: String.t()
  defp moved_message(%Riddle{season: %Season{} = season}, %{"season_id" => sent})
       when is_binary(sent) and sent != "" do
    if sent == to_string(season.id),
      do: "",
      else: ". Moved to #{season.name} to match Live date"
  end

  defp moved_message(_riddle, _params), do: ""

  # A failed save may have moved the Season to follow the Live date. Show the
  # Season the editor sent instead, so the next save is not read as the
  # editor picking the moved one.
  @spec keep_sent_season(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp keep_sent_season(changeset, %{"season_id" => sent}),
    do: Ecto.Changeset.cast(changeset, %{season_id: sent}, [:season_id])

  defp keep_sent_season(changeset, _params), do: changeset

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

  # A new riddle starts in the season holding its Live date, so typing a Live
  # date picks that season again. An edited riddle keeps its season here;
  # moving it with the Live date is the save's job.
  @spec follow_live_date(map(), [String.t()] | nil, map()) :: map()
  defp follow_live_date(
         %{"live_date" => %DateTime{} = live_date} = params,
         ["riddle", "live_date"],
         %{action: :new, seasons: seasons}
       ) do
    case Games.default_season(seasons, live_date) do
      nil -> params
      season -> Map.put(params, "season_id", season.id)
    end
  end

  defp follow_live_date(params, _target, _assigns), do: params

  @typep season_choice ::
           {:past, Season.t()} | :none | {:pick, [{String.t(), integer()}]}

  @spec season_choice(Riddle.t(), [Season.t()]) :: season_choice()
  defp season_choice(%Riddle{season: %Season{} = season}, seasons) do
    if Games.season_status(season) == :past,
      do: {:past, season},
      else: pick(seasons)
  end

  defp season_choice(%Riddle{}, seasons), do: pick(seasons)

  @spec pick([Season.t()]) :: season_choice()
  defp pick([]), do: :none
  defp pick(seasons), do: {:pick, Enum.map(seasons, &{&1.name, &1.id})}

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
