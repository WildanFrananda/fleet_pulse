defmodule FleetPulseWeb.DriverChannelTest do
  use FleetPulseWeb.ChannelCase

  import FleetPulse.TrackingFixtures

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.StateCache
  alias FleetPulseWeb.DriverSocket
  alias FleetPulseWeb.DriverToken

  setup do
    driver = driver_fixture()
    on_exit(fn -> cleanup(driver.id) end)

    {:ok, socket} = connect(DriverSocket, %{"token" => DriverToken.sign(driver.id)})

    %{driver: driver, socket: socket}
  end

  defp cleanup(driver_id) do
    _ = Tracking.stop_tracking(driver_id)
    _ = StateCache.delete(driver_id)
    :ok
  end

  defp join!(socket, driver_id) do
    {:ok, _reply, channel} = subscribe_and_join(socket, "driver:#{driver_id}")

    on_exit(fn ->
      if Process.alive?(channel.channel_pid), do: close(channel)
    end)

    channel
  end

  describe "connect/3" do
    test "accepts a valid token and assigns the driver", %{driver: driver} do
      assert {:ok, socket} = connect(DriverSocket, %{"token" => DriverToken.sign(driver.id)})
      assert socket.assigns.driver_id == driver.id
    end

    test "refuses a forged token" do
      assert {:error, :invalid_token} = connect(DriverSocket, %{"token" => "nope"})
    end

    test "refuses a connection carrying no token" do
      assert {:error, :missing_token} = connect(DriverSocket, %{})
    end
  end

  describe "join/3 authorisation" do
    test "a driver may join its own topic", %{driver: driver, socket: socket} do
      assert {:ok, _reply, _channel} = subscribe_and_join(socket, "driver:#{driver.id}")
    end

    test "a driver may NOT join another driver's topic", %{socket: socket} do
      victim = driver_fixture()
      on_exit(fn -> cleanup(victim.id) end)

      assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "driver:#{victim.id}")

      assert {:error, :not_found} = Tracking.fetch_state(victim.id)
    end

    test "rejects a topic id that is not a bare positive integer", %{socket: socket} do
      for bad <- ["abc", "7abc", "7.0", "0", "-1", ""] do
        assert {:error, %{reason: "invalid_topic"}} =
                 subscribe_and_join(socket, "driver:#{bad}"),
               "expected #{inspect(bad)} to be rejected"
      end
    end

    test "rejects a driver id that does not exist" do
      {:ok, socket} = connect(DriverSocket, %{"token" => DriverToken.sign(999_999_999)})

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, "driver:999999999")
    end

    test "marks the driver online", %{driver: driver, socket: socket} do
      join!(socket, driver.id)
      assert {:ok, %{status: :online}} = Tracking.fetch_driver(driver.id)
    end
  end

  describe "handle_in ping" do
    setup %{driver: driver, socket: socket} do
      %{channel: join!(socket, driver.id)}
    end

    test "accepts a well formed ping and updates live state", %{channel: channel, driver: driver} do
      ref =
        push(channel, "ping", %{
          "latitude" => -6.2,
          "longitude" => 106.816666,
          "recorded_at" => "2026-07-21T10:00:00Z",
          "speed_kmh" => 42
        })

      assert_reply ref, :ok

      assert {:ok, state} = Tracking.fetch_state(driver.id)
      assert state.coordinates == {-6.2, 106.816666}
      assert state.speed_kmh === 42.0
    end

    test "refuses telemetry outside the CHECK constraint bounds", %{channel: channel} do
      ref =
        push(channel, "ping", %{
          "latitude" => 999.0,
          "longitude" => 0.0,
          "recorded_at" => "2026-07-21T10:00:00Z"
        })

      assert_reply ref, :error, %{reason: "invalid_telemetry"}
    end

    test "refuses an unparseable timestamp", %{channel: channel} do
      ref =
        push(channel, "ping", %{
          "latitude" => -6.2,
          "longitude" => 106.8,
          "recorded_at" => "yesterday"
        })

      assert_reply ref, :error, %{reason: "invalid_telemetry"}
    end

    test "refuses an unknown event", %{channel: channel} do
      ref = push(channel, "teleport", %{})
      assert_reply ref, :error, %{reason: "unknown_event"}
    end
  end

  describe "handle_in status" do
    setup %{driver: driver, socket: socket} do
      %{channel: join!(socket, driver.id)}
    end

    test "accepts a known status", %{channel: channel, driver: driver} do
      ref = push(channel, "status", %{"status" => "busy"})

      assert_reply ref, :ok
      assert {:ok, %{status: :busy}} = Tracking.fetch_driver(driver.id)
    end

    test "refuses an unknown status without minting an atom for it", %{channel: channel} do
      status = "napping_#{System.unique_integer([:positive])}"
      ref = push(channel, "status", %{"status" => status})

      assert_reply ref, :error, %{reason: "invalid_status"}
      assert_raise ArgumentError, fn -> String.to_existing_atom(status) end
    end
  end

  describe "terminate/2" do
    test "marks the driver offline but keeps its process warm", %{driver: driver, socket: socket} do
      channel = join!(socket, driver.id)
      :ok = Tracking.track_location(driver.id, telemetry_attrs())
      {:ok, before} = Tracking.fetch_state(driver.id)

      Process.unlink(channel.channel_pid)
      :ok = close(channel)

      assert {:ok, %{status: :offline}} = Tracking.fetch_driver(driver.id)

      assert {:ok, warm} = Tracking.fetch_state(driver.id)
      assert warm.coordinates == before.coordinates
    end

    test "a refused join must not knock the authenticated driver offline",
         %{driver: driver, socket: socket} do
      join!(socket, driver.id)
      assert {:ok, %{status: :online}} = Tracking.fetch_driver(driver.id)

      victim = driver_fixture()
      on_exit(fn -> cleanup(victim.id) end)

      :ok = Tracking.subscribe_driver(driver.id)

      assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "driver:#{victim.id}")

      refute_receive {:driver_updated, %{status: :offline}}, 200
      assert {:ok, %{status: :online}} = Tracking.fetch_driver(driver.id)
    end
  end
end
