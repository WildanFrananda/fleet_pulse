defmodule FleetPulse.Tracking.EventsTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Tracking.Events

  test "fleet topic is stable" do
    assert Events.fleet_topic() == "drivers"
  end

  test "driver topic is namespaced per id" do
    assert Events.driver_topic(42) == "driver:42"
    refute Events.driver_topic(4) == Events.driver_topic(42)
  end
end
