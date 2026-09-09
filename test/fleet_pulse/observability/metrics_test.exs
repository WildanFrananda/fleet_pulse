defmodule FleetPulse.Observability.MetricsTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Observability.Metrics

  test "there is still no outbound gRPC client, which is why the client counter is not registered" do
    callers =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(&String.starts_with?(&1, "lib/fleet_pulse/proto/"))
      |> Enum.filter(&(&1 |> File.read!() |> String.contains?("GRPC.Stub.")))

    assert callers == [],
           """
           A gRPC client appeared in #{inspect(callers)}.

           kinetix_grpc_client_calls_total{peer, grpc_method, grpc_code} is part of the estate's
           contract for any service that calls another over gRPC, and this service was excused it
           only because it made no such call. Register it in FleetPulse.Observability.Metrics and
           count the call where it is made.
           """
  end

  test "the scrape carries the contract's names and no others of its own invention" do
    {:ok, body} = Metrics.scrape()

    assert body =~ "kinetix_build_info"
    refute body =~ "vm_memory"
    refute body =~ "phoenix_"
  end
end
