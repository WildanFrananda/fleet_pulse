defmodule FleetPulseWeb.MetricsControllerTest do
  use FleetPulseWeb.ConnCase, async: false

  @driver_id "8f3a1c2e-4b5d-6e7f-8a9b-0c1d2e3f4a5b"
  @correlation_id "c0ffee00-dead-beef-cafe-000000000001"

  defp scrape(conn) do
    response(get(conn, ~p"/metrics"), 200)
  end

  test "GET /metrics answers Prometheus text without a token", %{conn: conn} do
    conn = get(conn, ~p"/metrics")

    assert response(conn, 200) =~ "# HELP "
    assert response_content_type(conn, :text) =~ "text/plain"
  end

  test "names the estate's metrics, not the framework's", %{conn: conn} do
    get(conn, ~p"/health")

    body = scrape(build_conn())

    for metric <- ~w(
          kinetix_http_requests_total
          kinetix_http_request_duration_seconds_bucket
          kinetix_http_request_duration_seconds_sum
          kinetix_http_request_duration_seconds_count
          kinetix_build_info
        ) do
      assert body =~ ~r/^#{metric}[{ ]/m, "#{metric} is missing from the scrape"
    end
  end

  test "kinetix_build_info names this service and its version", %{conn: conn} do
    body = scrape(conn)

    assert body =~ ~s(kinetix_build_info{service="kinetix-matching-service",version=")
  end

  test "the route label is the template, never the id in the path", %{conn: conn} do
    get(conn, "/api/v1/drivers/#{@driver_id}")

    body = scrape(build_conn())

    assert body =~ ~s(route="/api/v1/drivers/{id}")
    refute body =~ @driver_id
  end

  test "a path the router does not serve collapses to one label", %{conn: conn} do
    get(conn, "/no/such/path/41")
    get(conn, "/no/such/path/42")

    body = scrape(build_conn())

    assert body =~ ~s(route="unmatched")
    refute body =~ ~s(route="/no/such/path/41")
  end

  test "no correlation id reaches a label", %{conn: conn} do
    conn
    |> put_req_header("x-request-id", @correlation_id)
    |> get(~p"/health")

    refute scrape(build_conn()) =~ @correlation_id
  end

  test "no label value carries a uuid or a long hex run", %{conn: conn} do
    get(conn, "/api/v1/drivers/#{@driver_id}")

    leaked =
      conn
      |> scrape()
      |> then(&Regex.scan(~r/[a-z_]+="[^"]*"/, &1))
      |> List.flatten()
      |> Enum.filter(&Regex.match?(~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}|[0-9a-f]{24,}/i, &1))

    assert leaked == []
  end

  test "the durations are in seconds, so the buckets are fractions of one", %{conn: conn} do
    get(conn, ~p"/health")

    assert scrape(build_conn()) =~ ~s(kinetix_http_request_duration_seconds_bucket)
    refute scrape(build_conn()) =~ "milliseconds"
  end
end
