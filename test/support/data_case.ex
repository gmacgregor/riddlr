defmodule Riddlr.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Riddlr.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  using do
    quote do
      alias Riddlr.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Riddlr.DataCase
    end
  end

  setup tags do
    Riddlr.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Riddlr.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Runs `fun` and returns its result with a real clock reading taken on each
  side of it.

  Oban's `schedule_in` reads the real clock, not `Riddlr.Clock`, so a frozen
  clock can't pin a job's `scheduled_at`. These two readings can: pass them to
  `assert_scheduled_in/3`.

      {{:ok, _}, window} = between_clock_reads(fn -> Games.transition(id, :live) end)
      assert_scheduled_in(job, 120, window)

  """
  @spec between_clock_reads((-> result)) :: {result, {DateTime.t(), DateTime.t()}}
        when result: term()
  def between_clock_reads(fun) do
    before = DateTime.utc_now()
    result = fun.()
    {result, {before, DateTime.utc_now()}}
  end

  @doc """
  Asserts that `job` is scheduled `seconds` after some instant inside `window`,
  as returned by `between_clock_reads/1`.
  """
  @spec assert_scheduled_in(Oban.Job.t(), integer(), {DateTime.t(), DateTime.t()}) :: true
  def assert_scheduled_in(%Oban.Job{scheduled_at: at}, seconds, {before, later}) do
    earliest = DateTime.add(before, seconds, :second)
    latest = DateTime.add(later, seconds, :second)

    assert DateTime.compare(at, earliest) != :lt and DateTime.compare(at, latest) != :gt,
           "expected #{inspect(at)} between #{inspect(earliest)} and #{inspect(latest)}"
  end
end
