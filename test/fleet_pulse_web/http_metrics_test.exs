defmodule FleetPulseWeb.HttpMetricsTest do
  use FleetPulseWeb.ConnCase, async: false

  @event [:kinetix, :http, :request, :stop]

  setup do
    test = self()
    handler = "http-metrics-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      @event,
      fn _event, measurements, metadata, _config ->
        send(test, {:counted, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    :ok
  end

  defp counted do
    receive do
      {:counted, measurements, metadata} -> {measurements, metadata}
    after
      0 -> flunk("the request was answered but never counted")
    end
  end

  defp count do
    receive do
      {:counted, _measurements, _metadata} -> 1 + count()
    after
      0 -> 0
    end
  end

  defp websocket_upgrade(path) do
    server =
      start_supervised!({Bandit, plug: FleetPulseWeb.Endpoint, port: 0, startup_log: false})

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw])

    request =
      "GET #{path} HTTP/1.1\r\n" <>
        "Host: localhost:#{port}\r\n" <>
        "Upgrade: websocket\r\n" <>
        "Connection: Upgrade\r\n" <>
        "Sec-WebSocket-Key: #{Base.encode64(:crypto.strong_rand_bytes(16))}\r\n" <>
        "Sec-WebSocket-Version: 13\r\n" <>
        "Origin: http://localhost\r\n\r\n"

    :ok = :gen_tcp.send(socket, request)
    {:ok, response} = :gen_tcp.recv(socket, 0, 5_000)
    :ok = :gen_tcp.close(socket)

    response |> String.split("\r\n") |> hd()
  end

  defp malformed_body(conn) do
    assert_raise Plug.Parsers.ParseError, fn ->
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/shipping/options", "{oops")
    end
  end

  describe "a request answered from the endpoint's own pipeline" do
    test "a body the parser cannot read is counted", %{conn: conn} do
      malformed_body(conn)

      assert {_measurements, %{status: "400", method: "POST"}} = counted()
    end

    test "the duration of one of those is recorded too", %{conn: conn} do
      malformed_body(conn)

      assert {%{duration: duration}, _metadata} = counted()
      assert duration > 0
    end
  end

  describe "a socket transport" do
    test "longpoll is an ordinary request, and is counted under its socket path", %{conn: conn} do
      get(conn, "/live/longpoll")

      assert {_measurements, %{route: "/live/longpoll", method: "GET"}} = counted()
    end

    test "an upgrade this endpoint rejects is counted", %{conn: conn} do
      get(conn, "/driver/websocket")

      assert {_measurements, %{route: "/driver/websocket"}} = counted()
    end

    test "a path under a socket that is not a transport cannot invent a label", %{conn: conn} do
      get(conn, "/live/8f3a1c2e-4b5d-6e7f-8a9b-0c1d2e3f4a5b")

      assert {_measurements, %{route: "unmatched"}} = counted()
    end

    test "a successful upgrade is counted as the 101 it answered with" do
      assert websocket_upgrade("/live/websocket?vsn=2.0.0") == "HTTP/1.1 101 Switching Protocols"

      assert {%{duration: duration}, %{route: "/live/websocket", status: "101"}} = counted()
      assert duration > 0
    end
  end

  describe "the boundary that was already right" do
    test "a route the router does serve keeps its template", %{conn: conn} do
      get(conn, "/api/v1/drivers/8f3a1c2e-4b5d-6e7f-8a9b-0c1d2e3f4a5b")

      assert {_measurements, %{route: "/api/v1/drivers/{id}"}} = counted()
    end

    test "a request the router answers is counted exactly once", %{conn: conn} do
      get(conn, "/no/such/path")

      assert count() == 1
    end
  end
end
