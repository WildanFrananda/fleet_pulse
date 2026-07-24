defmodule FleetPulseWeb.DriverSessionControllerTest do
  use FleetPulseWeb.ConnCase, async: true

  import FleetPulse.TrackingFixtures

  alias FleetPulse.Tracking
  alias FleetPulseWeb.DriverToken

  setup do
    driver = driver_fixture()
    {:ok, driver} = Tracking.set_driver_password(driver, "supersecret123")
    %{driver: driver}
  end

  test "issues a token that identifies the driver", %{conn: conn, driver: driver} do
    conn = post(conn, ~p"/driver/session", %{phone: driver.phone, password: "supersecret123"})
    body = json_response(conn, 201)

    assert body["driver_id"] == driver.id
    assert is_binary(body["token"])
    assert body["expires_in"] == DriverToken.max_age_seconds()
    assert {:ok, driver.id} == DriverToken.verify(body["token"])
  end

  test "rejects a wrong password", %{conn: conn, driver: driver} do
    conn = post(conn, ~p"/driver/session", %{phone: driver.phone, password: "wrong"})
    assert json_response(conn, 401)["error"] == "invalid_credentials"
  end

  test "rejects an unknown phone", %{conn: conn} do
    conn = post(conn, ~p"/driver/session", %{phone: "089999999999", password: "supersecret123"})
    assert json_response(conn, 401)["error"] == "invalid_credentials"
  end

  test "rejects a request missing the password", %{conn: conn} do
    conn = post(conn, ~p"/driver/session", %{phone: "081234567890"})
    assert json_response(conn, 400)["error"] =~ "required"
  end
end
