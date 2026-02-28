defmodule Riddlr.Games.Riddle do
  use Ecto.Schema
  import Ecto.Changeset

  @play_statuses ~w(closed scheduled ready live completed archived)
  @publish_statuses ~w(draft published)
  @difficulties ~w(easy medium hard expert)

  schema "riddles" do
    field :name, :string
    field :description, :string
    field :answers, {:array, :string}, default: []
    field :play_status, :string, default: "closed"
    field :solve_time, :integer
    field :category, :string
    field :difficulty, :string
    field :hint, :string
    field :hint_delay, :integer
    field :live_date, :utc_datetime
    field :publish_status, :string, default: "draft"
    field :first_solve_time, :integer
    field :completion_rate, :float
    field :average_solve_time, :float

    belongs_to :first_solver, Riddlr.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(riddle, attrs) do
    riddle
    |> cast(attrs, [
      :name,
      :description,
      :answers,
      :play_status,
      :solve_time,
      :category,
      :difficulty,
      :hint,
      :hint_delay,
      :live_date,
      :publish_status,
      :first_solver_id,
      :first_solve_time,
      :completion_rate,
      :average_solve_time
    ])
    |> validate_required([:name, :description, :answers, :solve_time])
    |> validate_answers()
    |> validate_inclusion(:play_status, @play_statuses)
    |> validate_inclusion(:publish_status, @publish_statuses)
    |> validate_inclusion(:difficulty, @difficulties, allow_nil: true)
    |> validate_number(:solve_time, greater_than: 0)
    |> validate_number(:hint_delay, greater_than_or_equal_to: 0)
    |> validate_number(:completion_rate, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
    |> validate_number(:average_solve_time, greater_than_or_equal_to: 0.0)
    |> foreign_key_constraint(:first_solver_id)
  end

  defp validate_answers(changeset) do
    changeset
    |> validate_length(:answers, min: 1, message: "must have at least one answer")
    |> validate_change(:answers, fn :answers, answers ->
      if Enum.all?(answers, &(is_binary(&1) && String.trim(&1) != "")) do
        []
      else
        [answers: "all answers must be non-empty strings"]
      end
    end)
  end

  def play_statuses, do: @play_statuses
  def publish_statuses, do: @publish_statuses
  def difficulties, do: @difficulties
end
