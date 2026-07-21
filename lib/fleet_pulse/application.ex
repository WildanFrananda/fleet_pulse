defmodule FleetPulse.Application do
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
      FleetPulse.Tracking.Supervisor,
      FleetPulseWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: FleetPulse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    FleetPulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
