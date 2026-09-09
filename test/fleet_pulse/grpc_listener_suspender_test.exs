defmodule FleetPulse.GrpcListenerSuspenderTest do
  # The drain flag is node-wide state.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FleetPulse.GrpcDrain
  alias FleetPulse.GrpcListenerSuspender
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

  defp start_suspender do
    capture_log(fn -> start_supervised!(GrpcListenerSuspender) end)
    :ok
  end

  defp stream do
    %GRPC.Server.Stream{
      service_name: "shipping.v1.ShippingService",
      method_name: "EstimateShippingOptions"
    }
  end

  test "says so at boot when the listener it would suspend is not there" do
    log = capture_log(fn -> start_supervised!(GrpcListenerSuspender) end)

    assert log =~ "no ranch listener named FleetPulse.GrpcEndpoint"
  end

  test "raises the refusal flag as it terminates, without waiting for anything" do
    start_drain()
    start_suspender()

    refute GrpcDrain.draining?()

    capture_log(fn -> stop_supervised!(GrpcListenerSuspender) end)

    assert GrpcDrain.draining?()
  end

  test "a new call arriving after it has terminated is refused with Unavailable" do
    start_drain()
    start_suspender()
    capture_log(fn -> stop_supervised!(GrpcListenerSuspender) end)

    error =
      assert_raise GRPC.RPCError, fn ->
        GrpcMetricsInterceptor.call(
          nil,
          stream(),
          fn _req, _stream ->
            flunk("the handler must not run once the listener is suspended")
          end,
          GrpcMetricsInterceptor.init([])
        )
      end

    assert error.status == GRPC.Status.unavailable()
  end

  test "terminating before the drain is running is not an error" do
    start_suspender()

    assert capture_log(fn -> stop_supervised!(GrpcListenerSuspender) end) == ""
  end
end
