defmodule FleetPulse.Observability.GrpcServerMetricsSeed do
  @moduledoc """
  Publishes `kinetix_grpc_server_calls_total` at zero for every method this endpoint serves, at boot.
  """

  alias FleetPulse.Observability.Metrics

  @seed %{count: 0}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    endpoint = Keyword.get(opts, :endpoint, FleetPulse.GrpcEndpoint)

    %{
      id: __MODULE__,
      start: {Task, :start_link, [fn -> seed(endpoint) end]},
      restart: :temporary,
      type: :worker
    }
  end

  @spec seed(module()) :: [String.t()]
  def seed(endpoint) do
    endpoint
    |> methods()
    |> Enum.map(&publish/1)
  end

  @spec methods(module()) :: [String.t()]
  def methods(endpoint) do
    endpoint.__meta__(:servers)
    |> Enum.flat_map(&server_methods/1)
  end

  @spec server_methods(module()) :: [String.t()]
  defp server_methods(server) do
    service = server.__meta__(:service)
    name = service.__meta__(:name)

    Enum.map(service.__rpc_calls__(), &"#{name}/#{elem(&1, 0)}")
  end

  @spec publish(String.t()) :: String.t()
  defp publish(method) do
    :telemetry.execute(Metrics.grpc_server_call_event(), @seed, %{
      grpc_method: method,
      grpc_code: GRPC.Status.code_name(GRPC.Status.ok())
    })

    method
  end
end
