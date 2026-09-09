defmodule FleetPulse.Application do
  @moduledoc false
  use Application

  @typep child :: Supervisor.child_spec() | {module(), term()} | module()

  @impl true
  @spec start(Application.start_type(), term()) ::
          {:ok, pid()} | {:ok, pid(), Application.state()} | {:error, term()}
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: FleetPulse.Supervisor)
  end

  @spec children() :: [child()]
  def children do
    core() ++
      grpc_children() ++ redispatcher() ++ [FleetPulseWeb.Endpoint] ++ grpc_shutdown_children()
  end

  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    FleetPulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @spec start_grpc_server() :: Supervisor.on_start()
  def start_grpc_server do
    FleetPulse.Security.PeerAuthorizationInterceptor.load_allowed_callers!()

    GRPC.Server.Supervisor.start_link(
      endpoint: FleetPulse.GrpcEndpoint,
      port: String.to_integer(System.fetch_env!("GRPC_PORT")),
      start_server: true,
      adapter_opts: [cred: grpc_credentials()]
    )
  end

  @spec core() :: [child()]
  defp core do
    [
      FleetPulse.Observability.Metrics,
      FleetPulseWeb.Telemetry,
      FleetPulse.Repo,
      {DNSCluster, query: Application.get_env(:fleet_pulse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FleetPulse.PubSub},
      FleetPulse.Tracking.Supervisor,
      {FleetPulse.RateLimit, clean_period: :timer.minutes(10)},
      FleetPulse.Security.TokenVerifier
    ]
  end

  @spec grpc_children() :: [child()]
  defp grpc_children do
    grpc_children(grpc_server?())
  end

  @spec grpc_children(boolean()) :: [child()]
  defp grpc_children(true) do
    [
      grpc_server_spec(),
      FleetPulse.Observability.GrpcServerMetricsSeed,
      GrpcReflection,
      FleetPulse.GrpcDrain
    ]
  end

  defp grpc_children(false), do: []

  @spec grpc_shutdown_children() :: [child()]
  defp grpc_shutdown_children do
    grpc_shutdown_children(grpc_server?())
  end

  @spec grpc_shutdown_children(boolean()) :: [child()]
  defp grpc_shutdown_children(true), do: [FleetPulse.GrpcListenerSuspender]
  defp grpc_shutdown_children(false), do: []

  @spec grpc_server?() :: boolean()
  defp grpc_server?, do: Application.get_env(:fleet_pulse, :start_grpc_server, true)

  @spec grpc_server_spec() :: Supervisor.child_spec()
  defp grpc_server_spec do
    %{
      id: GRPC.Server.Supervisor,
      start: {__MODULE__, :start_grpc_server, []},
      type: :supervisor
    }
  end

  @spec grpc_credentials() :: GRPC.Credential.t()
  defp grpc_credentials do
    FleetPulse.Security.ServiceIdentity.load!()
    |> FleetPulse.Security.ServiceIdentity.server_options()
    |> then(&GRPC.Credential.new(ssl: &1))
  end

  @spec redispatcher() :: [FleetPulse.Dispatch.ReDispatcher]
  defp redispatcher do
    :fleet_pulse
    |> Application.get_env(FleetPulse.Dispatch.ReDispatcher, [])
    |> Keyword.get(:enabled, true)
    |> redispatcher_child()
  end

  @spec redispatcher_child(boolean()) :: [FleetPulse.Dispatch.ReDispatcher]
  defp redispatcher_child(true), do: [FleetPulse.Dispatch.ReDispatcher]
  defp redispatcher_child(false), do: []
end
