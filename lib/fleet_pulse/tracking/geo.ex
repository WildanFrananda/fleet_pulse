defmodule FleetPulse.Tracking.Geo do
  @moduledoc """
  Pure geodesic helpers for proximity queries (PRD 5.3).

  No processes, no state, no ETS — just arithmetic, so every rule here is unit
  testable without starting anything.

  ## Why a bounding box at all

  `distance_km/2` costs four trigonometric calls. Running it against every
  cached driver would mean 40,000 trig calls per query at the PRD's fleet
  size. `bounding_box/2` and `within_box?/2` cost four float comparisons and
  no trigonometry, so they cheaply discard the overwhelming majority before
  the expensive step runs.

  ## The pre-filter must never exclude a true match

  The box is an optimisation, never an answer. Wherever the arithmetic gets
  awkward — near the poles, or when a span would cross the antimeridian — this
  module WIDENS the box instead of attempting wrap-around cleverness. A box
  that is too big only costs time; a box that is too small silently loses
  drivers, and `distance_km/2` never gets the chance to correct it.
  """

  alias FleetPulse.Types

  # Mean Earth radius (IUGG). One degree of latitude is 2*pi*R/360 km.
  @earth_radius_km 6371.0088
  @km_per_degree_lat 111.19492664455873

  # Below this cosine the longitude span explodes towards the poles, so we
  # stop computing it and take every longitude instead.
  @polar_cosine_floor 0.01

  @typedoc "An axis-aligned latitude/longitude rectangle."
  @type box :: %{
          min_lat: Types.latitude(),
          max_lat: Types.latitude(),
          min_lng: Types.longitude(),
          max_lng: Types.longitude()
        }

  @doc """
  Great-circle distance between two coordinates, in kilometres.
  """
  @spec distance_km(Types.coordinates(), Types.coordinates()) :: float()
  def distance_km({lat1, lng1}, {lat2, lng2}) do
    delta_lat = radians(lat2 - lat1)
    delta_lng = radians(lng2 - lng1)

    chord =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(radians(lat1)) * :math.cos(radians(lat2)) *
          :math.sin(delta_lng / 2) * :math.sin(delta_lng / 2)

    2 * @earth_radius_km * :math.atan2(:math.sqrt(chord), :math.sqrt(1 - chord))
  end

  @doc """
  The smallest safe rectangle enclosing every point within `radius_km`.

  Safe means never too small. See the module docs.
  """
  @spec bounding_box(Types.coordinates(), float()) :: box()
  def bounding_box({lat, lng}, radius_km) do
    delta_lat = radius_km / @km_per_degree_lat
    {min_lng, max_lng} = longitude_bounds(lng, longitude_delta(lat, radius_km))

    %{
      min_lat: clamp_latitude(lat - delta_lat),
      max_lat: clamp_latitude(lat + delta_lat),
      min_lng: min_lng,
      max_lng: max_lng
    }
  end

  @doc """
  Whether a coordinate falls inside a box. Cheap: no trigonometry.
  """
  @spec within_box?(Types.coordinates(), box()) :: boolean()
  def within_box?({lat, lng}, box) do
    lat >= box.min_lat and lat <= box.max_lat and
      lng >= box.min_lng and lng <= box.max_lng
  end

  @spec longitude_delta(Types.latitude(), float()) :: float()
  defp longitude_delta(lat, radius_km) do
    scaled_delta(:math.cos(radians(lat)), radius_km)
  end

  @spec scaled_delta(float(), float()) :: float()
  defp scaled_delta(cosine, _radius_km) when cosine < @polar_cosine_floor, do: 180.0
  defp scaled_delta(cosine, radius_km), do: radius_km / (@km_per_degree_lat * cosine)

  # Crossing +/-180 would need two disjoint ranges. Taking every longitude is
  # correct, far simpler, and only ever wastes work.
  @spec longitude_bounds(Types.longitude(), float()) ::
          {Types.longitude(), Types.longitude()}
  defp longitude_bounds(lng, delta) when lng - delta < -180.0 or lng + delta > 180.0 do
    {-180.0, 180.0}
  end

  defp longitude_bounds(lng, delta), do: {lng - delta, lng + delta}

  @spec clamp_latitude(float()) :: Types.latitude()
  defp clamp_latitude(lat) when lat < -90.0, do: -90.0
  defp clamp_latitude(lat) when lat > 90.0, do: 90.0
  defp clamp_latitude(lat), do: lat

  @spec radians(float()) :: float()
  defp radians(degrees), do: degrees * :math.pi() / 180.0
end
