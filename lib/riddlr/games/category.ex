defmodule Riddlr.Games.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "categories" do
    field :name, :string

    has_many :riddles, Riddlr.Games.Riddle

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 50)
    |> unique_constraint(:name)
  end
end
