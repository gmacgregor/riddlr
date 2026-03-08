defmodule Riddlr.Games.Riddle do
  @moduledoc """
  Riddle schema representing a puzzle in the system.

  ## Play Status Lifecycle

  Riddles transition through six play statuses in order:

      closed → scheduled → ready → live → completed → archived

  ### State Descriptions

  - **closed**: Initial state, not scheduled for play
  - **scheduled**: Published with live_date set, workers scheduled
  - **ready**: 5 minutes before live_date, ready to go live
  - **live**: Currently accepting answers from players
  - **completed**: First correct answer received, cooldown period starts
  - **archived**: Cooldown complete, riddle moved to archive

  ### Automatic Transitions

  State transitions are triggered by:

  1. **Manual scheduling**: Admin sets live_date + publish_status
  2. **Oban workers**: Time-based transitions (ready, live)
  3. **Player action**: First correct answer triggers completion
  4. **Cooldown timer**: Auto-archive after configurable delay

  ### Scheduling Behavior

  - **Rescheduling**: Changing live_date cancels old jobs and schedules new ones
  - **Draft rollback**: Moving to draft status cancels all pending workers
  - **Archive cooldown**: Configurable via `archive_cooldown_minutes` (default: 3)
    - Set to 0 to skip cooldown and archive immediately

  ### Example Flow

      # Publish riddle with live date
      {:ok, riddle} = Games.update_riddle(riddle, %{
        publish_status: "published",
        live_date: ~U[2026-04-01 14:00:00Z]
      })
      {:ok, riddle} = Games.schedule_riddle(riddle)
      # => play_status: "scheduled", 2 jobs scheduled

      # System automatically transitions:
      # - 13:55:00 => play_status: "ready"
      # - 14:00:00 => play_status: "live"
      # - [first correct answer] => play_status: "completed"
      # - [+3 minutes] => play_status: "archived"

  ## Fields

  See schema definition for complete field list.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @play_statuses ~w(closed scheduled ready live completed archived)
  @publish_statuses ~w(draft published)
  @difficulties ~w(easy medium hard expert)

  @solve_time 120
  @hint_delay 60

  @valid_transitions %{
    "closed" => ["scheduled"],
    "scheduled" => ["ready", "closed"],
    "ready" => ["live", "closed"],
    "live" => ["completed"],
    "completed" => ["archived"],
    "archived" => []
  }

  schema "riddles" do
    field :name, :string
    field :description, :string
    field :answers, {:array, :string}, default: []
    field :play_status, :string, default: "closed"
    field :solve_time, :integer, default: @solve_time
    field :difficulty, :string, default: "easy"
    field :hint, :string
    field :hint_delay, :integer, default: @hint_delay
    field :live_date, :utc_datetime
    field :publish_status, :string, default: "draft"
    field :first_solve_time, :integer
    field :completion_rate, :float
    field :average_solve_time, :float
    field :archive_cooldown_minutes, :integer, default: 3
    field :live_until_solved, :boolean, default: false

    belongs_to :category, Riddlr.Games.Category
    belongs_to :first_solver, Riddlr.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(riddle, attrs) do
    riddle
    |> cast(attrs, [
      :name,
      :description,
      :play_status,
      :solve_time,
      :category_id,
      :difficulty,
      :hint,
      :hint_delay,
      :live_date,
      :publish_status,
      :first_solver_id,
      :first_solve_time,
      :completion_rate,
      :average_solve_time,
      :archive_cooldown_minutes,
      :live_until_solved
    ])
    |> cast_answers(attrs)
    |> validate_required([:name, :description, :answers, :solve_time, :category_id])
    |> validate_answers()
    |> foreign_key_constraint(:category_id)
    |> validate_inclusion(:play_status, @play_statuses)
    |> validate_play_status_transition()
    |> validate_inclusion(:publish_status, @publish_statuses)
    |> validate_inclusion(:difficulty, @difficulties, allow_nil: true)
    |> validate_number(:solve_time, greater_than: 0)
    |> validate_number(:hint_delay, greater_than_or_equal_to: 0)
    |> validate_number(:completion_rate,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 100.0
    )
    |> validate_number(:average_solve_time, greater_than_or_equal_to: 0.0)
    |> validate_number(:archive_cooldown_minutes, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:first_solver_id)
  end

  defp cast_answers(changeset, attrs) do
    # Custom cast for answers to preserve empty strings for validation
    case Map.get(attrs, :answers) || Map.get(attrs, "answers") do
      nil ->
        changeset

      answers when is_list(answers) ->
        put_change(changeset, :answers, answers)

      _ ->
        changeset
    end
  end

  defp validate_answers(changeset) do
    # Get the answers value from changes or data to handle explicit empty arrays
    answers = get_field(changeset, :answers)

    changeset
    |> validate_change(:answers, fn :answers, _answers ->
      if length(answers) > 0 do
        []
      else
        [answers: "must have at least one answer"]
      end
    end)
    |> maybe_add_empty_answers_error(answers)
    |> validate_change(:answers, fn :answers, answers ->
      if Enum.all?(answers, &(is_binary(&1) && String.trim(&1) != "")) do
        []
      else
        [answers: "all answers must be non-empty strings"]
      end
    end)
  end

  defp maybe_add_empty_answers_error(changeset, answers) when is_list(answers) do
    if length(answers) == 0 do
      add_error(changeset, :answers, "must have at least one answer")
    else
      changeset
    end
  end

  defp maybe_add_empty_answers_error(changeset, _), do: changeset

  defp validate_play_status_transition(changeset) do
    case {changeset.data.id, get_change(changeset, :play_status)} do
      # New record, skip validation
      {nil, _} -> changeset
      # No status change
      {_, nil} -> changeset
      {_, new_status} -> validate_transition(changeset, changeset.data.play_status, new_status)
    end
  end

  defp validate_transition(changeset, current, new) when current == new, do: changeset
  defp validate_transition(changeset, nil, _new), do: changeset

  defp validate_transition(changeset, current, new) do
    if new in Map.get(@valid_transitions, current, []) do
      changeset
    else
      add_error(changeset, :play_status, "cannot transition from #{current} to #{new}")
    end
  end

  def play_statuses, do: @play_statuses
  def publish_statuses, do: @publish_statuses
  def difficulties, do: @difficulties
  def default_solve_time, do: @solve_time
  def default_hint_delay, do: @hint_delay
end
