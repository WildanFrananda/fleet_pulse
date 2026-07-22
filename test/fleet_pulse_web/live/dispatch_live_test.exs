defmodule FleetPulseWeb.DispatchLiveTest do
  use FleetPulseWeb.ConnCase

  import FleetPulse.TrackingFixtures

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.StateCache

  setup do
    Enum.each(StateCache.all(), &StateCache.delete(&1.driver_id))
    :ok
  end

  defp place!(latitude) do
    driver = driver_fixture()
    on_exit(fn -> cleanup(driver.id) end)

    {:ok, _pid} = Tracking.start_tracking(driver.id)
    {:ok, _driver} = Tracking.set_status(driver.id, :online)
    :ok = Tracking.track_location(driver.id, telemetry_attrs(%{latitude: latitude}))
    {:ok, _state} = Tracking.fetch_state(driver.id)

    driver
  end

  defp cleanup(driver_id) do
    _ = Tracking.stop_tracking(driver_id)
    _ = StateCache.delete(driver_id)
    :ok
  end

  test "renders the fleet already in memory at mount", %{conn: conn} do
    driver = place!(-6.2)

    {:ok, _view, html} = live(conn, ~p"/dispatch")

    assert html =~ "Dispatch"
    assert html =~ to_string(driver.id)
    assert html =~ "-6.2"
  end

  test "buffers a live update until the next flush", %{conn: conn} do
    driver = place!(-6.2)
    {:ok, view, _html} = live(conn, ~p"/dispatch")

    :ok = Tracking.track_location(driver.id, telemetry_attrs(%{latitude: -6.9}))
    {:ok, _state} = Tracking.fetch_state(driver.id)

    refute render(view) =~ "-6.9"

    send(view.pid, :flush)
    assert render(view) =~ "-6.9"
  end

  test "collapses repeated pings into one rendered update", %{conn: conn} do
    driver = place!(-6.2)
    {:ok, view, _html} = live(conn, ~p"/dispatch")

    for latitude <- [-6.3, -6.4, -6.5] do
      :ok = Tracking.track_location(driver.id, telemetry_attrs(%{latitude: latitude}))
    end

    {:ok, _state} = Tracking.fetch_state(driver.id)
    send(view.pid, :flush)

    html = render(view)
    assert html =~ "-6.5"
    refute html =~ "-6.3"
    refute html =~ "-6.4"
  end

  test "drops a driver from the table when it stops", %{conn: conn} do
    driver = place!(-6.2)
    {:ok, view, html} = live(conn, ~p"/dispatch")
    assert html =~ "-6.2"

    :ok = Tracking.stop_tracking(driver.id)

    assert render(view) =~ "0 driver(s) tracked"
    refute render(view) =~ "-6.2"
  end
end
