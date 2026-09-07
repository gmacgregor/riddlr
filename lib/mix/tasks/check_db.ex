defmodule Mix.Tasks.CheckDb do
  @moduledoc """
  Fails fast with a clear message when Postgres isn't reachable, instead of
  letting `ecto.create`/`ecto.migrate`/`mix test` fail with a wall of
  `DBConnection.ConnectionError` noise.
  """
  @shortdoc "Verifies Postgres is reachable before running DB-dependent tasks"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    config = Application.get_env(:riddlr, Riddlr.Repo, [])
    host = to_string(config[:hostname] || "localhost")
    port = config[:port] || 5432

    case :gen_tcp.connect(String.to_charlist(host), port, [active: false], 1_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        Mix.shell().error("""

        ✗ Can't reach Postgres at #{host}:#{port} (#{:inet.format_error(reason)}).

        `mix test` needs a running Postgres (it uses Ecto.Adapters.SQL.Sandbox,
        which runs each test in a real transaction). Start Postgres and retry, e.g.:

          brew services start postgresql
          # or however you normally run Postgres locally
        """)

        exit({:shutdown, 1})
    end
  end
end
