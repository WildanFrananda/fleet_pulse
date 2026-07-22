defmodule FleetPulse.Tracking.PersistenceBatcherTest do
  use FleetPulse.DataCase, async: false

  import FleetPulse.TrackingFixtures

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.LocationPing
  alias FleetPulse.Tracking.PersistenceBatcher
  alias FleetPulse.Tracking.StateCache

  setup do
    Enum.each(StateCache.all(), &StateCache.delete(&1.driver_id))

    driver = driver_fixture()
    start_supervised!(PersistenceBatcher)

    on_exit(fn ->
      _ = Tracking.stop_tracking(driver.id)
      _ = StateCache.delete(driver.id)
      :ok
    end)

    %{driver: driver}
  end

  defp pings_for(driver_id) do
    Repo.all(from(p in LocationPing, where: p.driver_id == ^driver_id))
  end

  test "persists a ping whose recorded_at carries only second precision", %{driver: driver} do
    {:ok, _} = Tracking.start_tracking(driver.id)
    recorded_at = DateTime.truncate(DateTime.utc_now(), :second)

    :ok =
      Tracking.track_location(
        driver.id,
        telemetry_attrs(%{recorded_at: recorded_at, speed_kmh: 42})
      )

    {:ok, _} = Tracking.fetch_state(driver.id)

    assert {:ok, 1} = PersistenceBatcher.flush_now()

    assert [ping] = pings_for(driver.id)
    assert ping.latitude == -6.2
    assert ping.speed_kmh == 42.0
    assert DateTime.compare(ping.recorded_at, recorded_at) == :eq
  end

  test "a second flush writes nothing for an unchanged driver", %{driver: driver} do
    {:ok, _} = Tracking.start_tracking(driver.id)
    :ok = Tracking.track_location(driver.id, telemetry_attrs())
    {:ok, _} = Tracking.fetch_state(driver.id)

    assert {:ok, 1} = PersistenceBatcher.flush_now()
    assert {:ok, 0} = PersistenceBatcher.flush_now()
    assert length(pings_for(driver.id)) == 1
  end

  test "skips a driver that has never reported a position", %{driver: driver} do
    {:ok, _} = Tracking.start_tracking(driver.id)

    assert {:ok, 0} = PersistenceBatcher.flush_now()
    assert pings_for(driver.id) == []
  end
end
