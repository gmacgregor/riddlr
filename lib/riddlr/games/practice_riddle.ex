defmodule Riddlr.Games.PracticeRiddle do
  @moduledoc """
  A riddle and its answer, shown on Home while nothing is scheduled.

  A practice riddle is not a `Riddlr.Games.Riddle`: it has no Play status,
  Live date, Guesses, Solves or Points. Nobody races; a player only peeks at
  the answer.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @description_max 500
  # Home draws one tile per character; more than this will not fit a phone.
  @answer_max 20

  schema "practice_riddles" do
    field :description, :string
    field :answer, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(practice_riddle, attrs) do
    practice_riddle
    |> cast(attrs, [:description, :answer])
    |> update_change(:description, &String.trim/1)
    |> update_change(:answer, &String.trim/1)
    |> validate_required([:description, :answer])
    |> validate_length(:description, max: @description_max)
    |> validate_length(:answer, max: @answer_max)
  end
end
