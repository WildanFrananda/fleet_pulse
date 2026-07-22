defmodule FleetPulse.Tracking.TelemetryTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Tracking.Telemetry

  @recorded_at ~U[2026-07-21 10:00:00Z]

  defp payload(overrides \\ %{}) do
    Map.merge(
      %{latitude: -6.2, longitude: 106.816666, recorded_at: @recorded_at},
      overrides
    )
  end

  describe "normalise/1 accepts" do
    test "a minimal payload, defaulting optional fields to nil" do
      assert {:ok, telemetry} = Telemetry.normalise(payload())
      assert telemetry.latitude == -6.2
      assert telemetry.speed_kmh == nil
      assert telemetry.bearing_deg == nil
    end

    test "integers, coercing them to floats" do
      attrs = %{latitude: 0, longitude: 0, speed_kmh: 42, bearing_deg: 90}
      assert {:ok, telemetry} = Telemetry.normalise(payload(attrs))

      assert telemetry.latitude === 0.0
      assert telemetry.longitude === 0.0
      assert telemetry.speed_kmh === 42.0
      assert telemetry.bearing_deg === 90.0
    end

    test "second precision, padding it to microsecond for for insert_all" do
      assert {:ok, telemetry} = Telemetry.normalise(payload())
      assert telemetry.recorded_at.microsecond == {0, 6}
    end

    test "every inclusive boundary the CHECK constrains allow" do
      assert {:ok, _} = Telemetry.normalise(payload(%{latitude: -90, longitude: -180}))
      assert {:ok, _} = Telemetry.normalise(payload(%{latitude: 90, longitude: 180}))
      assert {:ok, _} = Telemetry.normalise(payload(%{speed_kmh: 0}))
      assert {:ok, _} = Telemetry.normalise(payload(%{bearing_deg: 0}))
      assert {:ok, _} = Telemetry.normalise(payload(%{bearing_deg: 359.999}))
    end

    test "discarding unknown keys instead of passing them through" do
      assert {:ok, telemetry} = Telemetry.normalise(payload(%{admin: true, note: "x"}))

      assert Enum.sort(Map.keys(telemetry)) == [
               :bearing_deg,
               :latitude,
               :longitude,
               :recorded_at,
               :speed_kmh
             ]
    end
  end

  describe "normalise/1 rejects" do
    test "latitude outside -90..90" do
      for bad <- [-90.1, 90.1, 999.0] do
        assert {:error, :invalid_telemetry} = Telemetry.normalise(payload(%{latitude: bad}))
      end
    end

    test "longitude outside -180..180" do
      for bad <- [-180.1, 180.1] do
        assert {:error, :invalid_telemetry} = Telemetry.normalise(payload(%{longitude: bad}))
      end
    end

    test "bearing of exactly 360, because the upper bound is exclusive" do
      assert {:error, :invalid_telemetry} = Telemetry.normalise(payload(%{bearing_deg: 360.0}))
    end

    test "negative speed" do
      assert {:error, :invalid_telemetry} = Telemetry.normalise(payload(%{speed_kmh: -0.1}))
    end

    test "non-numeric values" do
      assert {:error, :invalid_telemetry} = Telemetry.normalise(payload(%{latitude: "-6.2"}))
      assert {:error, :invalid_telemetry} = Telemetry.normalise(payload(%{speed_kmh: :fast}))
    end

    test "a missing or wrongly typed recorded_at" do
      assert {:error, :invalid_telemetry} =
               Telemetry.normalise(Map.delete(payload(), :recorded_at))

      assert {:error, :invalid_telemetry} = Telemetry.normalise(payload(%{recorded_at: "now"}))
    end

    test "anything that is not a map" do
      for bad <- [nil, [], "payload", 42] do
        assert {:error, :invalid_telemetry} = Telemetry.normalise(bad)
      end
    end
  end
end
