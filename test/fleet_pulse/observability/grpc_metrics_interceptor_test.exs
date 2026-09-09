defmodule FleetPulse.Observability.GrpcMetricsInterceptorTest do
  # The in-flight counter is node-wide state.
  use ExUnit.Case, async: false

  alias FleetPulse.GrpcDrain
  alias FleetPulse.Observability.GrpcMetricsInterceptor

  @method "shipping.v1.ShippingService/EstimateShippingOptions"

  setup do
    test = self()
    handler = "grpc-metrics-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:kinetix, :grpc, :server, :call],
      fn _event, _measurements, metadata, _config -> send(test, {:counted, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, stream: stream()}
  end

  defp stream do
    %GRPC.Server.Stream{
      service_name: "shipping.v1.ShippingService",
      method_name: "EstimateShippingOptions"
    }
  end

  defp intercept(stream, next) do
    GrpcMetricsInterceptor.call(nil, stream, next, GrpcMetricsInterceptor.init([]))
  end

  test "counts an answered call as OK, under its full method name", %{stream: stream} do
    assert :answered = intercept(stream, fn _req, _stream -> :answered end)

    assert_received {:counted, %{grpc_method: @method, grpc_code: "OK"}}
  end

  test "counts a refused call under the status it was refused with", %{stream: stream} do
    refuse = fn _req, _stream ->
      raise GRPC.RPCError, status: GRPC.Status.permission_denied(), message: "no"
    end

    assert_raise GRPC.RPCError, fn -> intercept(stream, refuse) end

    assert_received {:counted, %{grpc_method: @method, grpc_code: "PermissionDenied"}}
  end

  test "counts a handler that crashed for some other reason as Unknown", %{stream: stream} do
    assert_raise RuntimeError, fn ->
      intercept(stream, fn _req, _stream -> raise "boom" end)
    end

    assert_received {:counted, %{grpc_code: "Unknown"}}
  end

  test "counts a handler that exited as Unknown, and lets the exit through", %{stream: stream} do
    assert catch_exit(intercept(stream, fn _req, _stream -> exit(:bye) end)) == :bye

    assert_received {:counted, %{grpc_code: "Unknown"}}
  end

  describe "the in-flight count the drain waits on" do
    test "returns to where it started when a call succeeds", %{stream: stream} do
      before = GrpcDrain.in_flight()

      intercept(stream, fn _req, _stream -> :answered end)

      assert GrpcDrain.in_flight() == before
    end

    test "returns to where it started when a call raises", %{stream: stream} do
      before = GrpcDrain.in_flight()

      assert_raise RuntimeError, fn ->
        intercept(stream, fn _req, _stream -> raise "boom" end)
      end

      assert GrpcDrain.in_flight() == before
    end
  end

  test "falls back to a bounded label when the stream names no method" do
    intercept(%GRPC.Server.Stream{}, fn _req, _stream -> :answered end)

    assert_received {:counted, %{grpc_method: "unknown"}}
  end
end
