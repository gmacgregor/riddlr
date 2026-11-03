defmodule Riddlr.Accounts.Scope do
  @moduledoc """
  Says who is calling a context function.

  A user scope carries the signed-in user, or no user for a guest. Context
  write functions take a scope and check its permissions themselves, so the
  web layer cannot forget to.

  The system scope stands for the app itself: seeds and jobs that write data
  with no user behind them. It holds every permission.
  """

  alias Riddlr.Accounts.User

  defstruct user: nil, system?: false

  @type t :: %__MODULE__{user: User.t() | nil, system?: boolean()}

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  @spec for_user(User.t() | nil) :: t() | nil
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Creates the system scope, for writes that no user makes.
  """
  @spec for_system() :: t()
  def for_system, do: %__MODULE__{system?: true}
end
