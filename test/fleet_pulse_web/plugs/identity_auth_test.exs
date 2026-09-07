defmodule FleetPulseWeb.Plugs.IdentityAuthTest do
  use FleetPulseWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias FleetPulse.Security.TokenVerifier

  defp with_identity_down(fun) do
    live = System.fetch_env!("IDENTITY_JWKS_URL")
    System.put_env("IDENTITY_JWKS_URL", "http://127.0.0.1:1/.well-known/jwks.json")
    restart_verifier()

    try do
      fun.()
    after
      System.put_env("IDENTITY_JWKS_URL", live)
      restart_verifier()
    end
  end

  defp restart_verifier do
    :ok = Supervisor.terminate_child(FleetPulse.Supervisor, TokenVerifier)
    {:ok, _pid} = Supervisor.restart_child(FleetPulse.Supervisor, TokenVerifier)
    :ok
  end

  setup %{conn: conn} do
    %{conn: conn |> authenticate(role: "seller") |> put_req_header("accept", "application/json")}
  end

  test "answers 503 when identity could not be reached to check the token", %{conn: conn} do
    {conn, log} =
      with_log(fn -> with_identity_down(fn -> get(conn, ~p"/api/v1/drivers") end) end)

    assert json_response(conn, 503)["error"] == "identity_unavailable"
    assert log =~ "did not return a JWKS"
  end

  test "answers 401 to a token identity's keys do not verify", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer not.a.token")
      |> get(~p"/api/v1/drivers")

    assert json_response(conn, 401)["error"] == "unauthorized"
  end

  test "lets a token identity signed through", %{conn: conn} do
    assert %{"data" => _drivers} = conn |> get(~p"/api/v1/drivers") |> json_response(200)
  end
end
