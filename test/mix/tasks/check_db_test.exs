defmodule Mix.Tasks.CheckDbTest do
  # Swaps the Repo config, which every other DB test reads.
  use ExUnit.Case, async: false

  alias Mix.Tasks.CheckDb

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "passes when Postgres is reachable" do
    assert :ok = CheckDb.run([])
  end

  test "exits with an error naming the host and port when Postgres is not reachable" do
    port = closed_port()
    config = Application.get_env(:riddlr, Riddlr.Repo)

    Application.put_env(
      :riddlr,
      Riddlr.Repo,
      Keyword.merge(config, hostname: "127.0.0.1", port: port)
    )

    on_exit(fn -> Application.put_env(:riddlr, Riddlr.Repo, config) end)

    assert catch_exit(CheckDb.run([])) == {:shutdown, 1}
    assert_received {:mix_shell, :error, [message]}
    assert message =~ "127.0.0.1:#{port}"
  end

  # A port nothing listens on: bind one, note it, let it go.
  @spec closed_port() :: :inet.port_number()
  defp closed_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
