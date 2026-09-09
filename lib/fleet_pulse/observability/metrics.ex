defmodule FleetPulse.Observability.Metrics do
  @moduledoc """
  The estate's metric vocabulary, and the Prometheus registry that serves it.
  """

  import Telemetry.Metrics, only: [counter: 2, distribution: 2, last_value: 2, sum: 2]

  @registry :kinetix_prometheus
  @service "kinetix-matching-service"

  @http_stop [:kinetix, :http, :request, :stop]
  @grpc_server_call [:kinetix, :grpc, :server, :call]
  @build_info [:kinetix, :build, :info]

  @buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

  @spec http_stop_event() :: :telemetry.event_name()
  def http_stop_event, do: @http_stop

  @spec grpc_server_call_event() :: :telemetry.event_name()
  def grpc_server_call_event, do: @grpc_server_call

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    TelemetryMetricsPrometheus.Core.child_spec(
      name: @registry,
      metrics: definitions(),
      start_async: false
    )
  end

  @spec scrape() :: {:ok, String.t()} | {:error, String.t()}
  def scrape do
    :telemetry.execute(@build_info, %{value: 1}, %{service: @service, version: version()})

    {:ok, TelemetryMetricsPrometheus.Core.scrape(@registry)}
  rescue
    error -> {:error, Exception.format(:error, error, __STACKTRACE__)}
  catch
    :exit, reason -> {:error, Exception.format_exit(reason)}
  end

  @spec definitions() :: [Telemetry.Metrics.t()]
  def definitions do
    [
      counter("kinetix.http.requests.total",
        event_name: @http_stop,
        tags: [:method, :route, :status],
        description: "HTTP requests answered, by method, matched route template and status."
      ),
      distribution("kinetix.http.request.duration.seconds",
        event_name: @http_stop,
        measurement: :duration,
        unit: {:native, :second},
        tags: [:method, :route],
        reporter_options: [buckets: @buckets],
        description: "Time to answer an HTTP request, in seconds."
      ),
      sum("kinetix.grpc.server.calls.total",
        event_name: @grpc_server_call,
        measurement: :count,
        tags: [:grpc_method, :grpc_code],
        description: "gRPC calls this server answered, by method and canonical status code."
      ),
      last_value("kinetix.build.info",
        event_name: @build_info,
        measurement: :value,
        tags: [:service, :version],
        description: "Always 1. Carries the service name and version as labels."
      )
    ]
  end

  @spec version() :: String.t()
  defp version, do: :fleet_pulse |> Application.spec(:vsn) |> to_version()

  @spec to_version(charlist() | nil) :: String.t()
  defp to_version(nil), do: "unknown"
  defp to_version(vsn), do: to_string(vsn)
end
