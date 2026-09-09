defmodule FleetPulse.Observability.GrpcServerMetricsSeedTest do
  # Stands up a Prometheus registry of its own, and telemetry handlers are node-wide.
  use ExUnit.Case, async: false

  alias FleetPulse.Observability.GrpcServerMetricsSeed
  alias FleetPulse.Observability.Metrics

  @registry :grpc_server_metrics_seed_test
  @family "kinetix_grpc_server_calls_total"
  @shipping "shipping.v1.ShippingService/EstimateShippingOptions"

  setup do
    start_supervised!(
      {TelemetryMetricsPrometheus.Core,
       name: @registry, metrics: Metrics.definitions(), start_async: false}
    )

    :ok
  end

  defp scrape, do: TelemetryMetricsPrometheus.Core.scrape(@registry)

  defp series(body) do
    body
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, @family <> "{"))
  end

  test "a registry nothing has called is missing the family entirely, which is why we seed it" do
    body = scrape()

    refute body =~ @family,
           """
           The exporter no longer drops a registered-but-unobserved family, so the boot-time seed
           in FleetPulse.Observability.GrpcServerMetricsSeed may no longer be needed. Check
           deps/telemetry_metrics_prometheus_core/lib/core/exporter.ex before deleting it.
           """
  end

  test "after the seed the family is served, before any call has been made" do
    GrpcServerMetricsSeed.seed(FleetPulse.GrpcEndpoint)

    body = scrape()

    assert body =~ "# HELP #{@family}"
    assert body =~ "# TYPE #{@family} counter"
    assert series(body) != []
  end

  test "every seeded series says zero, because zero calls have been answered" do
    GrpcServerMetricsSeed.seed(FleetPulse.GrpcEndpoint)

    for line <- series(scrape()) do
      assert String.ends_with?(line, "} 0"),
             "the seed published a call that never happened: #{line}"
    end
  end

  test "the seed names every method the endpoint declares, exactly as the interceptor names them" do
    methods = GrpcServerMetricsSeed.seed(FleetPulse.GrpcEndpoint)

    assert @shipping in methods
    assert "fleet.v1.CourierTelemetryService/DispatchCourier" in methods
    assert "fleet.v1.CourierTelemetryService/StreamDriverLocation" in methods

    body = scrape()

    for method <- methods do
      assert body =~ ~s(grpc_method="#{method}"), "#{method} was not published"
    end
  end

  test "a real call adds to the seeded series rather than starting a second one" do
    GrpcServerMetricsSeed.seed(FleetPulse.GrpcEndpoint)

    :telemetry.execute(Metrics.grpc_server_call_event(), %{count: 1}, %{
      grpc_method: @shipping,
      grpc_code: "OK"
    })

    lines = Enum.filter(series(scrape()), &String.contains?(&1, @shipping))

    assert [line] = Enum.filter(lines, &String.contains?(&1, ~s(grpc_code="OK")))
    assert String.ends_with?(line, "} 1")
  end
end
