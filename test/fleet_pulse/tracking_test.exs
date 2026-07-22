defmodule FleetPulse.TrackingTest do
  use FleetPulse.DataCase, async: false

  import FleetPulse.TrackingFixtures

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.DriverRegistry
  alias FleetPulse.Tracking.StateCache

  setup do
    driver = driver_fixture()
    on_exit(fn -> cleanup(driver.id) end)
    %{driver: driver}
  end

  defp cleanup(driver_id) do
    _ = Tracking.stop_tracking(driver_id)
    _ = StateCache.delete(driver_id)
    :ok
  end

  defp track!(driver) do
    {:ok, pid} = Tracking.start_tracking(driver.id)
    pid
  end

  defp await_new_pid(driver_id, old_pid, attempts \\ 100)
  defp await_new_pid(_driver_id, _old_pid, 0), do: :timeout

  defp await_new_pid(driver_id, old_pid, attempts) do
    case DriverRegistry.whereis(driver_id) do
      {:ok, pid} when pid != old_pid ->
        pid

      _not_yet ->
        Process.sleep(10)
        await_new_pid(driver_id, old_pid, attempts - 1)
    end
  end

  describe "start_tracking/1" do
    test "rehydrates status from the drivers table", %{driver: driver} do
      {:ok, _} = Tracking.set_status(driver.id, :busy)
      track!(driver)

      assert {:ok, state} = Tracking.fetch_state(driver.id)
      assert state.status == :busy
      assert state.coordinates == nil
    end

    test "is idempotent for an already tracked driver", %{driver: driver} do
      pid = track!(driver)
      assert {:ok, ^pid} = Tracking.start_tracking(driver.id)
    end

    test "refuses a driver that does not exist" do
      assert {:error, :not_found} = Tracking.start_tracking(999_999_999)
    end
  end

  describe "track_location/2" do
    test "stores normalised telemetry", %{driver: driver} do
      track!(driver)

      assert :ok = Tracking.track_location(driver.id, telemetry_attrs(%{speed_kmh: 42}))

      assert {:ok, state} = Tracking.fetch_state(driver.id)
      assert state.coordinates == {-6.2, 106.816666}
      assert state.speed_kmh === 42.0
    end

    test "rejects bad telemetry without disturbing the process", %{driver: driver} do
      track!(driver)
      {:ok, before} = Tracking.fetch_state(driver.id)

      assert {:error, :invalid_telemetry} =
               Tracking.track_location(driver.id, telemetry_attrs(%{latitude: 999.0}))

      assert {:ok, ^before} = Tracking.fetch_state(driver.id)
    end

    test "reports an untracked driver", %{driver: driver} do
      assert {:error, :not_found} = Tracking.track_location(driver.id, telemetry_attrs())
    end
  end

  describe "set_status/2" do
    test "writes through to both the database and the live process", %{driver: driver} do
      track!(driver)

      assert {:ok, updated} = Tracking.set_status(driver.id, :busy)
      assert updated.status == :busy
      assert {:ok, %{status: :busy}} = Tracking.fetch_driver(driver.id)
      assert {:ok, %{status: :busy}} = Tracking.fetch_state(driver.id)
    end

    test "records the status even when nobody is tracking the driver", %{driver: driver} do
      assert {:ok, _} = Tracking.set_status(driver.id, :online)
      assert {:ok, %{status: :online}} = Tracking.fetch_driver(driver.id)
    end

    test "status survives a cold restart with an empty cache", %{driver: driver} do
      track!(driver)
      {:ok, _} = Tracking.set_status(driver.id, :busy)

      :ok = Tracking.stop_tracking(driver.id)
      assert {:error, :not_found} = StateCache.fetch(driver.id)

      track!(driver)
      assert {:ok, %{status: :busy}} = Tracking.fetch_state(driver.id)
    end
  end

  describe "stop_tracking/1" do
    test "evicts the cache entry and announces the stop", %{driver: driver} do
      driver_id = driver.id
      track!(driver)
      :ok = Tracking.subscribe_driver(driver_id)

      assert :ok = Tracking.stop_tracking(driver_id)

      assert_receive {:driver_stopped, ^driver_id}
      assert {:error, :not_found} = StateCache.fetch(driver_id)
    end
  end

  describe "crash recovery" do
    test "an abnormal death keeps the cache and the replacement reuses it", %{driver: driver} do
      pid = track!(driver)
      :ok = Tracking.track_location(driver.id, telemetry_attrs())
      {:ok, before} = Tracking.fetch_state(driver.id)

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert {:ok, _} = StateCache.fetch(driver.id)

      new_pid = await_new_pid(driver.id, pid)
      assert is_pid(new_pid)

      assert {:ok, restored} = Tracking.fetch_state(driver.id)
      assert restored.coordinates == before.coordinates
    end
  end

  describe "broadcasts" do
    test "the fleet topic sees every driver", %{driver: driver} do
      driver_id = driver.id
      :ok = Tracking.subscribe_fleet()

      track!(driver)

      assert_receive {:driver_updated, %{driver_id: ^driver_id}}
    end

    test "a driver topic ignores other drivers", %{driver: driver} do
      other = driver_fixture()
      on_exit(fn -> cleanup(other.id) end)

      :ok = Tracking.subscribe_driver(driver.id)

      track!(other)
      :ok = Tracking.track_location(other.id, telemetry_attrs())

      refute_receive {:driver_updated, _}, 100
    end
  end
end
