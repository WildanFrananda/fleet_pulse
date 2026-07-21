defmodule FleetPulse.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  @spec start(Application.start_type(), term()) ::
          {:ok, pid()} | {:ok, pid(), Application.state()} | {:error, term()}
  def start(_type, _args) do
    children = [
      FleetPulseWeb.Telemetry,
      FleetPulse.Repo,
      {DNSCluster, query: Application.get_env(:fleet_pulse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FleetPulse.PubSub},
      FleetPulse.Tracking.DriverRegistry,
      FleetPulse.Tracking.DriverSupervisor,
      FleetPulseWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FleetPulse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    FleetPulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
