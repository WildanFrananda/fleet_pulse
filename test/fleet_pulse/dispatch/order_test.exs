defmodule FleetPulse.Dispatch.OrderTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Dispatch.Order

  defp changeset(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          pickup_latitude: -6.2,
          pickup_longitude: 106.8,
          dropoff_latitude: -6.9,
          dropoff_longitude: 107.6,
          weight_kg: 100
        },
        overrides
      )

    Order.changeset(%Order{}, attrs)
  end

  test "accepts a valid order" do
    assert changeset().valid?
  end

  test "defaults status to :pending and leaves it unassigned" do
    assert %Order{}.status == :pending
    assert %Order{}.driver_id == nil
  end

  test "requires both pickup and dropoff coordinates" do
    refute Order.changeset(%Order{}, %{}).valid?
  end

  test "enforces coordinate ranges matching the CHECK constraints" do
    refute changeset(%{pickup_latitude: 90.1}).valid?
    refute changeset(%{dropoff_longitude: -180.1}).valid?
    assert changeset(%{pickup_latitude: 90, dropoff_longitude: -180}).valid?
  end

  test "keeps weight within the allowed range" do
    refute changeset(%{weight_kg: -1}).valid?
    refute changeset(%{weight_kg: 5_001}).valid?
    assert changeset(%{weight_kg: 0}).valid?
  end

  test "statuses/0 matches the DB CHECK constraint" do
    assert Order.statuses() == [:pending, :assigned, :picked_up, :delivered, :cancelled]
  end
end
