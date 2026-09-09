defmodule FleetPulse.GrpcDrainTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FleetPulse.GrpcDrain
  alias FleetPulse.Observability.GrpcMetricsInterceptor

  @counters {FleetPulse.GrpcDrain, :counters}

  setup do
    on_exit(fn -> :persistent_term.erase(@counters) end)
    :ok
  end

  defp start_drain do
    capture_log(fn -> start_supervised!(GrpcDrain) end)
    :ok
  end

  defp stream do
    %GRPC.Server.Stream{
      service_name: "shipping.v1.ShippingService",
      method_name: "EstimateShippingOptions"
    }
  end

  defp intercept(next) do
    GrpcMetricsInterceptor.call(nil, stream(), next, GrpcMetricsInterceptor.init([]))
  end

  test "counts nothing and refuses nothing when it is not running" do
    assert GrpcDrain.in_flight() == 0
    refute GrpcDrain.draining?()
    assert GrpcDrain.entered() == :ok
    assert GrpcDrain.left() == :ok
  end

  test "says so at boot when the listener it would suspend is not there" do
    log = capture_log(fn -> start_supervised!(GrpcDrain) end)

    assert log =~ "no ranch listener named FleetPulse.GrpcEndpoint"
  end

  test "holds the count of the calls currently running" do
    start_drain()

    assert GrpcDrain.in_flight() == 0

    intercept(fn _req, _stream ->
      assert GrpcDrain.in_flight() == 1
      :answered
    end)

    assert GrpcDrain.in_flight() == 0
  end

  describe "once draining" do
    setup do
      start_drain()
      capture_log(fn -> stop_supervised!(GrpcDrain) end)
      :ok
    end

    test "the flag stays raised for the rest of the shutdown" do
      assert GrpcDrain.draining?()
    end

    test "a call arriving on an already-open connection is refused with Unavailable" do
      error =
        assert_raise GRPC.RPCError, fn ->
          intercept(fn _req, _stream -> flunk("the handler must not run while draining") end)
        end

      assert error.status == GRPC.Status.unavailable()
    end
  end

  test "reports a clean drain when nothing was in flight" do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    start_drain()

    assert capture_log(fn -> stop_supervised!(GrpcDrain) end) =~
             "gRPC drained; no calls left in flight"
  end

  test "reports what it could not wait out rather than claiming a clean drain" do
    Application.put_env(:fleet_pulse, GrpcDrain, budget_ms: 100)
    on_exit(fn -> Application.put_env(:fleet_pulse, GrpcDrain, budget_ms: 5_000) end)

    start_drain()
    GrpcDrain.entered()

    log = capture_log(fn -> stop_supervised!(GrpcDrain) end)

    assert log =~ "drain budget expired with 1 call(s) still in flight"
  end
end
