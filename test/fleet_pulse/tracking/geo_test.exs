defmodule FleetPulse.Tracking.GeoTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Tracking.Geo

  defp offset({lat, lng}, north_km, east_km) do
    per_degree = 111.19492664455873

    {lat + north_km / per_degree,
     lng + east_km / (per_degree * :math.cos(lat * :math.pi() / 180))}
  end

  describe "distance_km/2" do
    test "is zero for a point and itself" do
      assert Geo.distance_km({-6.2, 106.8}, {-6.2, 106.8}) == 0.0
    end

    test "one degree of latitude is about 111.19 km, anywhere" do
      assert_in_delta Geo.distance_km({0.0, 0.0}, {1.0, 0.0}), 111.19, 0.01
      assert_in_delta Geo.distance_km({50.0, 20.0}, {51.0, 20.0}), 111.19, 0.01
    end

    test "one degree of longitude shrinks with latitude" do
      at_equator = Geo.distance_km({0.0, 0.0}, {0.0, 1.0})
      at_sixty = Geo.distance_km({60.0, 0.0}, {60.0, 1.0})

      assert_in_delta at_equator, 111.19, 0.01
      # cos(60 degrees) = 0.5, so the same degree spans half the ground.
      assert_in_delta at_sixty, at_equator / 2, 0.05
    end

    test "is symmetric" do
      jakarta = {-6.2088, 106.8456}
      bandung = {-6.9175, 107.6191}

      assert_in_delta Geo.distance_km(jakarta, bandung),
                      Geo.distance_km(bandung, jakarta),
                      0.000001
    end

    test "matches a known city pair" do
      # Jakarta to Bandung is roughly 118 km great-circle.
      assert_in_delta Geo.distance_km({-6.2088, 106.8456}, {-6.9175, 107.6191}), 118.0, 2.0
    end
  end

  describe "bounding_box/2" do
    test "encloses the query point itself" do
      centre = {-6.2, 106.8}
      assert Geo.within_box?(centre, Geo.bounding_box(centre, 3.0))
    end

    test "never excludes a point that is genuinely within the radius" do
      centre = {-6.2, 106.8}
      radius = 3.0
      box = Geo.bounding_box(centre, radius)

      for north <- [-1.0, -0.5, 0.0, 0.5, 1.0], east <- [-1.0, -0.5, 0.0, 0.5, 1.0] do
        point = offset(centre, north * radius * 0.7, east * radius * 0.7)
        distance = Geo.distance_km(centre, point)

        if distance <= radius do
          assert Geo.within_box?(point, box),
                 "#{inspect(point)} is #{distance} km away yet the pre-filter dropped it"
        end
      end
    end

    test "excludes a point far outside the radius" do
      box = Geo.bounding_box({-6.2, 106.8}, 3.0)
      refute Geo.within_box?({-6.9175, 107.6191}, box)
    end

    test "widens to every longitude near the poles instead of exploding" do
      box = Geo.bounding_box({89.9, 0.0}, 3.0)

      assert box.min_lng == -180.0
      assert box.max_lng == 180.0
      assert box.max_lat <= 90.0
    end

    test "widens to every longitude rather than wrapping the antimeridian" do
      box = Geo.bounding_box({0.0, 179.9}, 50.0)

      assert box.min_lng == -180.0
      assert box.max_lng == 180.0
    end

    test "clamps latitude instead of producing an impossible one" do
      box = Geo.bounding_box({-89.99, 0.0}, 100.0)

      assert box.min_lat == -90.0
      assert box.min_lat >= -90.0
      assert box.max_lat <= 90.0
    end
  end
end
