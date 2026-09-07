defmodule FleetPulseWeb.HealthControllerTest do
  use FleetPulseWeb.ConnCase, async: true

  test "GET /health is alive without touching the database", %{conn: conn} do
    assert json_response(get(conn, ~p"/health"), 200) == %{
             "status" => "ok",
             "service" => "kinetix-matching-service"
           }
  end

  test "GET /health names no framework, version or port", %{conn: conn} do
    body = json_response(get(conn, ~p"/health"), 200)

    assert Map.keys(body) |> Enum.sort() == ["service", "status"]
  end

  test "GET /health/ready confirms the database is reachable", %{conn: conn} do
    assert json_response(get(conn, ~p"/health/ready"), 200) == %{
             "status" => "ok",
             "database" => "reachable"
           }
  end
end
