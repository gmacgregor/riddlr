defmodule Riddlr.Games do
  @moduledoc """
  The Games context.
  """

  import Ecto.Query, warn: false
  alias Riddlr.Repo

  alias Riddlr.Games.Riddle

  @doc """
  Returns the list of riddles.

  ## Examples

      iex> list_riddles()
      [%Riddle{}, ...]

  """
  def list_riddles do
    Repo.all(Riddle)
  end

  @doc """
  Gets a single riddle.

  Raises `Ecto.NoResultsError` if the Riddle does not exist.

  ## Examples

      iex> get_riddle!(123)
      %Riddle{}

      iex> get_riddle!(456)
      ** (Ecto.NoResultsError)

  """
  def get_riddle!(id), do: Repo.get!(Riddle, id)

  @doc """
  Creates a riddle.

  ## Examples

      iex> create_riddle(%{field: value})
      {:ok, %Riddle{}}

      iex> create_riddle(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_riddle(attrs \\ %{}) do
    %Riddle{}
    |> Riddle.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a riddle.

  ## Examples

      iex> update_riddle(riddle, %{field: new_value})
      {:ok, %Riddle{}}

      iex> update_riddle(riddle, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_riddle(%Riddle{} = riddle, attrs) do
    riddle
    |> Riddle.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a riddle.

  ## Examples

      iex> delete_riddle(riddle)
      {:ok, %Riddle{}}

      iex> delete_riddle(riddle)
      {:error, %Ecto.Changeset{}}

  """
  def delete_riddle(%Riddle{} = riddle) do
    Repo.delete(riddle)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking riddle changes.

  ## Examples

      iex> change_riddle(riddle)
      %Ecto.Changeset{data: %Riddle{}}

  """
  def change_riddle(%Riddle{} = riddle, attrs \\ %{}) do
    Riddle.changeset(riddle, attrs)
  end
end
