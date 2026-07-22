defmodule FleetPulse.Tracking.LocationPingTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Tracking.LocationPing

  defp changeset(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          driver_id: 1,
          latitude: -6.2,
          longitude: 106.816666,
          recorded_at: DateTime.utc_now()
        },
        overrides
      )

    LocationPing.changeset(%LocationPing{}, attrs)
  end

  test "accepts a valid ping" do
    assert changeset().valid?
  end

  test "requires driver_id, coordinates and recorded_at" do
    refute LocationPing.changeset(%LocationPing{}, %{}).valid?
  end

  test "enforces the same coordinate bounds as the CHECK constraints" do
    refute changeset(%{latitude: 90.1}).valid?
    refute changeset(%{latitude: -90.1}).valid?
    refute changeset(%{longitude: 180.1}).valid?
    assert changeset(%{latitude: 90, longitude: 180}).valid?
  end

  test "rejects negative speed and out-of-range bearing" do
    refute changeset(%{speed_kmh: -1.0}).valid?
    refute changeset(%{bearing_deg: 360.0}).valid?
    assert changeset(%{speed_kmh: 0.0, bearing_deg: 359.9}).valid?
  end
end
