defmodule Riddlr.Games.Practice do
  @moduledoc """
  Practice riddles: the riddles Home shows while no game is scheduled.

  `Riddlr.Games` delegates its `*_practice_riddle*` functions here, so callers
  outside the context go through `Riddlr.Games`. Every write rebuilds the
  Home snapshot.
  """

  import Ecto.Query, warn: false

  alias Riddlr.Accounts.Scope
  alias Riddlr.Authorization
  alias Riddlr.Games
  alias Riddlr.Games.PracticeRiddle
  alias Riddlr.Repo

  @doc """
  Returns every practice riddle, oldest first.
  """
  @spec list() :: [PracticeRiddle.t()]
  def list do
    Repo.all(from p in PracticeRiddle, order_by: p.id)
  end

  @doc """
  Creates a practice riddle.
  """
  @spec create(Scope.t(), map()) ::
          {:ok, PracticeRiddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def create(%Scope{} = scope, attrs) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      %PracticeRiddle{}
      |> PracticeRiddle.changeset(attrs)
      |> Repo.insert()
      |> tap(&refresh_home_on_ok/1)
    end
  end

  @doc """
  Gets a practice riddle. Raises `Ecto.NoResultsError` if there is none.
  """
  @spec get!(integer() | String.t()) :: PracticeRiddle.t()
  def get!(id), do: Repo.get!(PracticeRiddle, id)

  @doc """
  Gets a practice riddle, or nil if there is none with that id.
  """
  @spec get(integer()) :: PracticeRiddle.t() | nil
  def get(id), do: Repo.get(PracticeRiddle, id)

  @doc """
  Updates a practice riddle.
  """
  @spec update(Scope.t(), PracticeRiddle.t(), map()) ::
          {:ok, PracticeRiddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def update(%Scope{} = scope, %PracticeRiddle{} = practice_riddle, attrs) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      practice_riddle
      |> PracticeRiddle.changeset(attrs)
      |> Repo.update()
      |> tap(&refresh_home_on_ok/1)
    end
  end

  @doc """
  Deletes a practice riddle.
  """
  @spec delete(Scope.t(), PracticeRiddle.t()) ::
          {:ok, PracticeRiddle.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def delete(%Scope{} = scope, %PracticeRiddle{} = practice_riddle) do
    with :ok <- Authorization.authorize(scope, :manage_riddles) do
      practice_riddle
      |> Repo.delete()
      |> tap(&refresh_home_on_ok/1)
    end
  end

  @spec refresh_home_on_ok({:ok, PracticeRiddle.t()} | {:error, term()}) :: :ok
  defp refresh_home_on_ok({:ok, _}), do: Games.refresh_home()
  defp refresh_home_on_ok(_error), do: :ok

  @doc "Returns a blank practice riddle for a new-practice-riddle form."
  @spec new() :: PracticeRiddle.t()
  def new, do: %PracticeRiddle{}

  @doc """
  Returns a changeset for a practice riddle form.
  """
  @spec change(PracticeRiddle.t(), map()) :: Ecto.Changeset.t()
  def change(%PracticeRiddle{} = practice_riddle, attrs \\ %{}) do
    PracticeRiddle.changeset(practice_riddle, attrs)
  end

  @doc """
  Picks a practice riddle at random, or returns nil when there are none.

  Pass the id of the one on screen as `exclude_id` to get a different one
  ("Another riddle"). With only that one left, this returns nil.
  """
  @spec random(integer() | nil) :: PracticeRiddle.t() | nil
  def random(exclude_id \\ nil) do
    PracticeRiddle
    |> exclude_practice_riddle(exclude_id)
    |> order_by(fragment("RANDOM()"))
    |> limit(1)
    |> Repo.one()
  end

  @spec exclude_practice_riddle(Ecto.Queryable.t(), integer() | nil) :: Ecto.Query.t()
  defp exclude_practice_riddle(query, nil), do: from(p in query)
  defp exclude_practice_riddle(query, id), do: from(p in query, where: p.id != ^id)

  @doc """
  Counts the practice riddles: the M in "Practice riddle N of M".
  """
  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(PracticeRiddle, :count)

  @doc """
  The place of a practice riddle among all of them, oldest first, counting
  from 1: the N in "Practice riddle N of M".
  """
  @spec number(PracticeRiddle.t()) :: non_neg_integer()
  def number(%PracticeRiddle{id: id}) do
    Repo.aggregate(from(p in PracticeRiddle, where: p.id <= ^id), :count)
  end
end
