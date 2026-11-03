defmodule Riddlr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Riddlr.Gameplay.EtsOwner,
      RiddlrWeb.Telemetry,
      Riddlr.Vault,
      Riddlr.Repo,
      {Oban, Application.fetch_env!(:riddlr, Oban)},
      {DNSCluster, query: Application.get_env(:riddlr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Riddlr.PubSub},
      Riddlr.Gameplay.Presence,
      # Bounded, so a flood of guesses cannot spawn moderation tasks without
      # limit. When full, moderation is skipped (see Riddlr.Gameplay).
      {Task.Supervisor,
       name: Riddlr.ModerationSupervisor,
       max_children:
         :riddlr
         |> Application.get_env(Riddlr.ModerationSupervisor, [])
         |> Keyword.get(:max_children, 200)},
      {Registry, keys: :unique, name: Riddlr.GameClockRegistry},
      {DynamicSupervisor, name: Riddlr.GameClockSupervisor, strategy: :one_for_one},
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
