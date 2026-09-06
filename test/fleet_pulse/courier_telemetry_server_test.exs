defmodule FleetPulse.CourierTelemetryServerTest do
  use FleetPulse.DataCase, async: false
  alias FleetPulse.CourierTelemetryServer
  alias FleetPulse.Proto.Fleet.V1.DispatchCourierRequest
  import FleetPulse.TrackingFixtures

  test "dispatch_courier/2 handles dispatch requests from OMS" do
    _driver = driver_fixture(%{status: :online})

    req = %DispatchCourierRequest{
      merchant_principal_id: "11111111-2222-3333-4444-555555555555",
      order_id: "888",
      order_number: "ORD-ELIXIR-888"
    }

    res = CourierTelemetryServer.dispatch_courier(req, nil)

    assert res.success == true
    assert String.starts_with?(res.dispatch_ref, "DISP-")
  end
end
