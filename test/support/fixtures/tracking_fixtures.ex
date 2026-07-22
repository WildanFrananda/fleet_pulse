defmodule FleetPulse.TrackingFixtures do
  @moduledoc """
  Test data builders for the tracking domain.

  Every builder generates unique `phone` and `vehicle_plate` values, because
  both carry a unique index. Tests that need a specific value pass it in as an
  override rather than hardcoding one that a parallel test might also claim.
  """

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.Driver

  @typedoc "Attributes accepted by `FleetPulse.Tracking.create_driver/1`."
  @type driver_attrs :: %{
          required(:name) => term(),
          required(:phone) => term(),
          required(:vehicle_plate) => term(),
          required(:capacity_kg) => term(),
          optional(atom()) => term()
        }

  @typedoc "A raw device payload, before `FleetPulse.Tracking.Telemetry.normalise/1`."
  @type telemetry_attrs :: %{
          required(:latitude) => term(),
          required(:longitude) => term(),
          required(:recorded_at) => term(),
          optional(atom()) => term()
        }

  @doc """
  Valid attributes for `FleetPulse.Tracking.create_driver/1`.
  """
  @spec driver_attrs(map()) :: driver_attrs()
  def driver_attrs(overrides \\ %{}) do
    unique = System.unique_integer([:positive])

    Map.merge(
      %{
        name: "Driver #{unique}",
        phone: "08" <> String.pad_leading(to_string(rem(unique, 100_000_000)), 8, "0"),
        vehicle_plate: "b #{rem(unique, 10_000)} test",
        capacity_kg: 100
      },
      overrides
    )
  end

  @doc """
  Inserts a driver and returns it.
  """
  @spec driver_fixture(map()) :: Driver.t()
  def driver_fixture(overrides \\ %{}) do
    {:ok, driver} = Tracking.create_driver(driver_attrs(overrides))
    driver
  end

  @doc """
  A raw telemetry payload, as a device would send it — NOT yet normalised.
  """
  @spec telemetry_attrs(map()) :: driver_attrs()
  def telemetry_attrs(overrides \\ %{}) do
    Map.merge(
      %{latitude: -6.2, longitude: 106.816666, recorded_at: DateTime.utc_now()},
      overrides
    )
  end
end
