defmodule FleetPulse.Tracking.IdleReaperTest do
  use FleetPulse.DataCase, async: false

  import FleetPulse.TrackingFixtures

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Tracking.IdleReaper
  alias FleetPulse.Tracking.StateCache

  setup do
    Enum.each(StateCache.all(), &StateCache.delete(&1.driver_id))
    :ok
  end

  defp tracked!(status) do
    driver = driver_fixture()
    {:ok, _pid} = Tracking.start_tracking(driver.id)
    {:ok, _driver} = Tracking.set_status(driver.id, status)
    on_exit(fn -> cleanup(driver.id) end)
    driver
  end

  defp cleanup(driver_id) do
    _ = Tracking.stop_tracking(driver_id)
    _ = StateCache.delete(driver_id)
    :ok
  end

  defp future_cutoff, do: DateTime.add(DateTime.utc_now(), 60, :second)

  describe "DriverState.stop_if_idle/2" do
    test "stops an offline driver and evicts its cache entry" do
      driver = tracked!(:offline)
      driver_id = driver.id
      :ok = Tracking.subscribe_driver(driver_id)

      assert :stopped = DriverState.stop_if_idle(driver_id, future_cutoff())

      assert_receive {:driver_stopped, ^driver_id}
      assert {:error, :not_found} = StateCache.fetch(driver_id)
      assert {:error, :not_found} = Tracking.fetch_state(driver_id)
    end

    test "leaves an online driver running even with a wide open cutoff" do
      driver = tracked!(:online)

      assert :active = DriverState.stop_if_idle(driver.id, future_cutoff())
      assert {:ok, %{status: :online}} = Tracking.fetch_state(driver.id)
    end

    test "leaves a busy driver running" do
      driver = tracked!(:busy)

      assert :active = DriverState.stop_if_idle(driver.id, future_cutoff())
      assert {:ok, %{status: :busy}} = Tracking.fetch_state(driver.id)
    end

    test "reports a driver that is not tracked at all" do
      driver = driver_fixture()

      assert {:error, :not_found} = DriverState.stop_if_idle(driver.id, future_cutoff())
    end

    test "a stale CACHE entry cannot get a live driver killed" do
      driver = tracked!(:online)

      {:ok, live} = Tracking.fetch_state(driver.id)
      stale = %{live | status: :offline, synced_at: ~U[2020-01-01 00:00:00.000000Z]}
      :ok = StateCache.put(driver.id, stale)

      assert DriverState.idle?(stale, future_cutoff())
      assert :active = DriverState.stop_if_idle(driver.id, future_cutoff())
    end
  end

  describe "reap_now/0" do
    setup do
      Application.put_env(:fleet_pulse, IdleReaper,
        enabled: true,
        interval_ms: 60_000,
        idle_after_ms: 1
      )

      on_exit(fn -> Application.put_env(:fleet_pulse, IdleReaper, enabled: false) end)

      start_supervised!(IdleReaper)
      :ok
    end

    test "sweeps idle drivers and spares the rest" do
      idle = tracked!(:offline)
      working = tracked!(:online)

      Process.sleep(10)

      assert {:ok, 1} = IdleReaper.reap_now()

      assert {:error, :not_found} = Tracking.fetch_state(idle.id)
      assert {:ok, %{status: :online}} = Tracking.fetch_state(working.id)
    end

    test "reports nothing to do when every driver is active" do
      tracked!(:online)
      Process.sleep(10)

      assert {:ok, 0} = IdleReaper.reap_now()
    end
  end
end
