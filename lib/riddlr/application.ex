defmodule Riddlr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RiddlrWeb.Telemetry,
      Riddlr.Repo,
      {Oban, Application.fetch_env!(:riddlr, Oban)},
      {DNSCluster, query: Application.get_env(:riddlr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Riddlr.PubSub},
      # Start a worker by calling: Riddlr.Worker.start_link(arg)
      # {Riddlr.Worker, arg},
      # Start to serve requests, typically the last entry
      RiddlrWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Riddlr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RiddlrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
