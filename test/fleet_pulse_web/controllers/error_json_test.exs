defmodule FleetPulseWeb.ErrorJSONTest do
  use FleetPulseWeb.ConnCase, async: true

  test "renders 404 with the status message and a trace id" do
    assert FleetPulseWeb.ErrorJSON.render("404.json", %{}) ==
             %{errors: %{detail: "Not Found"}, traceId: "-"}
  end

  test "renders 500 without naming the failure, and says what was not changed" do
    assert FleetPulseWeb.ErrorJSON.render("500.json", %{}) ==
             %{
               errors: %{
                 detail:
                   "something went wrong handling this request. No dispatch, assignment or " <>
                     "location was changed unless a previous response said so."
               },
               traceId: "-"
             }
  end

  test "carries the correlation id the request arrived with" do
    Logger.metadata(request_id: "F-abc123")

    assert %{traceId: "F-abc123"} = FleetPulseWeb.ErrorJSON.render("500.json", %{})
    assert %{traceId: "F-abc123"} = FleetPulseWeb.ErrorJSON.render("422.json", %{})
  end

  test "falls back to a dash when no correlation id was set" do
    Logger.metadata(request_id: nil)

    assert %{traceId: "-"} = FleetPulseWeb.ErrorJSON.render("503.json", %{})
  end
end
