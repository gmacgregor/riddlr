defmodule Riddlr.Release do
  @moduledoc """
  Database tasks for a release, where Mix is not installed. Fly runs
  `migrate/0` through `bin/migrate` before each deploy (`release_command` in
  fly.toml). Run `rollback/2` by hand with
  `bin/riddlr eval 'Riddlr.Release.rollback(Riddlr.Repo, 20260101000000)'`.
  """
  @app :riddlr

  @doc "Runs every pending migration for each repo."
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Rolls `repo` back down to migration `version`."
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @spec repos() :: [module()]
  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  @spec load_app() :: :ok | {:error, term()}
  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
