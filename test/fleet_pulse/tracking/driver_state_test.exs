defmodule FleetPulse.Tracking.DriverStateTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Tracking.DriverState

  @cutoff ~U[2026-07-21 10:00:00.000000Z]
  @before ~U[2026-07-21 09:59:59.000000Z]
  @after_ ~U[2026-07-21 10:00:01.000000Z]

  defp state(overrides) do
    struct!(%DriverState{driver_id: 1}, overrides)
  end

  describe "idle?/2" do
    test "an offline driver last committed before the cutoff is idle" do
      assert DriverState.idle?(state(status: :offline, synced_at: @before), @cutoff)
    end

    test "an offline driver committed after the cutoff is not yet idle" do
      refute DriverState.idle?(state(status: :offline, synced_at: @after_), @cutoff)
    end

    test "an online driver is never idle, however long it has been quiet" do
      refute DriverState.idle?(state(status: :online, synced_at: @before), @cutoff)
    end

    test "a busy driver is never idle either" do
      refute DriverState.idle?(state(status: :busy, synced_at: @before), @cutoff)
    end

    test "a state that has never been committed is not idle" do
      refute DriverState.idle?(state(status: :offline, synced_at: nil), @cutoff)
    end
  end
end
