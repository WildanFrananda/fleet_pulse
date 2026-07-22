defmodule FleetPulse.Tracking.EventsTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Tracking.Events

  test "fleet topic is stable" do
    assert Events.fleet_topic() == "tracking:fleet"
  end

  test "driver topic is namespaced per id" do
    assert Events.driver_topic(42) == "tracking:driver:42"
    refute Events.driver_topic(4) == Events.driver_topic(42)
  end

  test "domain topics cannot collide with channel topics" do
    refute Events.driver_topic(42) == "driver:42"
    refute String.starts_with?(Events.fleet_topic(), "driver:")
  end
end
