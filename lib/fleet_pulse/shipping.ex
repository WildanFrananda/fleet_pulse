defmodule FleetPulse.Shipping do
  @moduledoc """
  Shipping Fee & Courier Option Calculation Engine (PRD shipping_courier_selection_prd).
  Calculates Geodesic distance, evaluates courier tier limits, and computes shipping rates.
  """

  alias FleetPulse.Tracking.Geo
  alias FleetPulse.Types

  @type coords :: %{latitude: float(), longitude: float()}

  @doc """
  Calculates available shipping options and rates for a given origin and destination.
  """
  @spec calculate_options(coords(), coords(), float(), integer() | nil) :: map()
  def calculate_options(origin, destination, weight_kg, merchant_principal_id \\ nil) do
    _merchant_principal_id = merchant_principal_id
    dist_km = Geo.distance_km(to_coordinates(origin), to_coordinates(destination))
    rounded_dist = Float.round(dist_km, 2)

    options = [
      build_instant_option(rounded_dist, weight_kg),
      build_sameday_option(rounded_dist, weight_kg),
      build_regular_option(rounded_dist, weight_kg),
      build_cargo_option(rounded_dist, weight_kg)
    ]

    %{
      distance_km: rounded_dist,
      options: options
    }
  end

  @spec to_coordinates(coords()) :: Types.coordinates()
  defp to_coordinates(%{latitude: latitude, longitude: longitude}) do
    {latitude, longitude}
  end

  defp build_instant_option(dist_km, weight_kg) do
    is_available = dist_km <= 15.0 && weight_kg <= 10.0
    reason =
      cond do
        dist_km > 15.0 -> "Distance exceeds 15km limit"
        weight_kg > 10.0 -> "Weight exceeds 10kg limit"
        true -> nil
      end

    base_fee = 15_000.0 + (dist_km * 3_000.0)

    %{
      service_tier: "KINETIX_INSTANT",
      service_name: "Kinetix Express Instant",
      distance_km: dist_km,
      base_shipping_fee: Float.round(base_fee, 2),
      estimated_delivery_time: "1 - 2 Jam",
      is_available: is_available,
      unavailable_reason: reason
    }
  end

  defp build_sameday_option(dist_km, weight_kg) do
    is_available = dist_km <= 30.0 && weight_kg <= 20.0
    reason =
      cond do
        dist_km > 30.0 -> "Distance exceeds 30km limit"
        weight_kg > 20.0 -> "Weight exceeds 20kg limit"
        true -> nil
      end

    base_fee = 12_000.0 + (dist_km * 2_000.0)

    %{
      service_tier: "KINETIX_SAMEDAY",
      service_name: "Kinetix SameDay",
      distance_km: dist_km,
      base_shipping_fee: Float.round(base_fee, 2),
      estimated_delivery_time: "6 - 8 Jam",
      is_available: is_available,
      unavailable_reason: reason
    }
  end

  defp build_regular_option(dist_km, weight_kg) do
    is_available = dist_km <= 500.0 && weight_kg <= 30.0
    reason =
      cond do
        dist_km > 500.0 -> "Distance exceeds 500km limit"
        weight_kg > 30.0 -> "Weight exceeds 30kg limit"
        true -> nil
      end

    hundred_km_units = max(1.0, Float.round(dist_km / 100.0, 1))
    base_fee = 9_000.0 + (weight_kg * 1_500.0 * hundred_km_units)

    %{
      service_tier: "KINETIX_REGULAR",
      service_name: "Kinetix Regular Freight",
      distance_km: dist_km,
      base_shipping_fee: Float.round(base_fee, 2),
      estimated_delivery_time: "1 - 3 Hari",
      is_available: is_available,
      unavailable_reason: reason
    }
  end

  defp build_cargo_option(dist_km, weight_kg) do
    is_available = weight_kg >= 10.0
    reason = if weight_kg < 10.0, do: "Cargo is reserved for packages >= 10kg", else: nil

    base_fee = 25_000.0 + (weight_kg * 1_000.0)

    %{
      service_tier: "KINETIX_CARGO",
      service_name: "Kinetix Cargo Heavy",
      distance_km: dist_km,
      base_shipping_fee: Float.round(base_fee, 2),
      estimated_delivery_time: "3 - 5 Hari",
      is_available: is_available,
      unavailable_reason: reason
    }
  end
end
