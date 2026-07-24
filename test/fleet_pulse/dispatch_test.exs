defmodule FleetPulse.DispatchTest do
  use FleetPulse.DataCase, async: false

  import FleetPulse.TrackingFixtures

  alias FleetPulse.Dispatch
  alias FleetPulse.Dispatch.Events
  alias FleetPulse.Dispatch.Order
  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.StateCache

  @pickup {-6.1754, 106.8272}

  setup do
    Enum.each(StateCache.all(), &StateCache.delete(&1.driver_id))
    :ok
  end

  defp north({lat, lng}, km), do: {lat + km / 111.19492664455873, lng}

  defp online_driver(distance_km, capacity_kg) do
    {lat, lng} = north(@pickup, distance_km)
    driver = driver_fixture(%{capacity_kg: capacity_kg})
    on_exit(fn -> cleanup(driver.id) end)

    {:ok, _pid} = Tracking.start_tracking(driver.id)
    {:ok, _driver} = Tracking.set_status(driver.id, :online)
    :ok = Tracking.track_location(driver.id, telemetry_attrs(%{latitude: lat, longitude: lng}))
    {:ok, _state} = Tracking.fetch_state(driver.id)

    driver
  end

  defp cleanup(driver_id) do
    _ = Tracking.stop_tracking(driver_id)
    _ = StateCache.delete(driver_id)
    :ok
  end

  defp order!(overrides \\ %{}) do
    {:ok, order} = Dispatch.create_order(order_attrs(overrides))
    order
  end

  defp assigned_order! do
    {:ok, order} = Dispatch.assign_order(order!().id)
    order
  end

  defp order_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        pickup_latitude: elem(@pickup, 0),
        pickup_longitude: elem(@pickup, 1),
        dropoff_latitude: -6.9,
        dropoff_longitude: 107.6,
        weight_kg: 100
      },
      overrides
    )
  end

  describe "assign_order/2" do
    test "assigns the nearest eligible driver and marks it busy" do
      _far = online_driver(2.0, 100)
      near = online_driver(0.5, 100)

      order = order!()

      assert {:ok, assigned} = Dispatch.assign_order(order.id)
      assert assigned.status == :assigned
      assert assigned.driver_id == near.id
      assert assigned.assigned_at != nil

      assert {:ok, %{status: :busy}} = Tracking.fetch_state(near.id)
    end

    test "skips drivers that cannot carry the load" do
      _small = online_driver(0.5, 50)
      big = online_driver(2.0, 500)

      assert {:ok, assigned} = Dispatch.assign_order(order!(%{weight_kg: 200}).id)
      assert assigned.driver_id == big.id
    end

    test "fails when no driver is in range" do
      _far = online_driver(50.0, 100)

      assert {:error, :no_driver_available} = Dispatch.assign_order(order!().id)
    end

    test "refuses to assign an order that is not pending" do
      online_driver(0.5, 100)
      order = order!()
      {:ok, _} = Dispatch.assign_order(order.id)

      assert {:error, :already_assigned} = Dispatch.assign_order(order.id)
    end

    test "reports an order that does not exist" do
      assert {:error, :not_found} = Dispatch.assign_order(999_999_999)
    end

    test "does not claim a driver when assignment finds none" do
      near = online_driver(0.5, 50)
      assert {:error, :no_driver_available} = Dispatch.assign_order(order!(%{weight_kg: 500}).id)

      assert {:ok, %{status: :online}} = Tracking.fetch_state(near.id)
    end

    test "broadcasts the assignment on the driver's dispatch topic" do
      driver = online_driver(0.5, 100)
      :ok = Events.subscribe_driver(driver.id)

      order = order!()
      assert {:ok, _assigned} = Dispatch.assign_order(order.id)

      assert_receive {:order_assigned, %Order{id: id, driver_id: assigned_to}}
      assert id == order.id
      assert assigned_to == driver.id
    end
  end

  describe "concurrent assignment" do
    test "two orders racing for one driver get different drivers" do
      d1 = online_driver(0.5, 100)
      d2 = online_driver(0.5, 100)

      orders = [order!(), order!()]

      results =
        orders
        |> Task.async_stream(fn order -> Dispatch.assign_order(order.id) end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, _}, &1))

      assigned_ids = Enum.map(results, fn {:ok, order} -> order.driver_id end)

      assert Enum.sort(assigned_ids) == Enum.sort([d1.id, d2.id])
    end

    test "many claims on ONE driver yield exactly one winner" do
      driver = online_driver(0.5, 100)

      orders = for _ <- 1..20, do: order!()

      results =
        orders
        |> Task.async_stream(fn order -> Dispatch.assign_order(order.id) end,
          max_concurrency: 20,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      winners = Enum.filter(results, &match?({:ok, _}, &1))
      losers = Enum.filter(results, &match?({:error, :no_driver_available}, &1))

      assert length(winners) == 1
      assert length(losers) == 19

      assert [{:ok, won}] = winners
      assert won.driver_id == driver.id
      assert {:ok, %{status: :busy}} = Tracking.fetch_state(driver.id)
    end
  end

  describe "order lifecycle" do
    test "advances assigned -> picked_up -> delivered and frees the driver" do
      driver = online_driver(0.5, 100)
      order = assigned_order!()
      assert {:ok, %{status: :busy}} = Tracking.fetch_state(driver.id)

      assert {:ok, %{status: :picked_up}} = Dispatch.mark_picked_up(order.id, driver.id)
      assert {:ok, %{status: :delivered}} = Dispatch.mark_delivered(order.id, driver.id)

      assert {:ok, %{status: :online}} = Tracking.fetch_state(driver.id)
    end

    test "refuses a pickup by a driver who does not own the order" do
      owner = online_driver(0.5, 100)
      intruder = online_driver(2.0, 100)

      {:ok, order} = Dispatch.assign_order(order!().id)
      assert order.driver_id == owner.id, "expected the nearer driver to be assigned"

      assert {:error, :forbidden} = Dispatch.mark_picked_up(order.id, intruder.id)
    end

    test "refuses delivery before pickup" do
      driver = online_driver(0.5, 100)
      order = assigned_order!()

      assert {:error, :invalid_transition} = Dispatch.mark_delivered(order.id, driver.id)
    end

    test "refuses a pickup on an order the driver was never assigned" do
      driver = online_driver(0.5, 100)
      {:ok, order} = Dispatch.create_order(order_attrs())

      assert {:error, :forbidden} = Dispatch.mark_picked_up(order.id, driver.id)
    end

    test "cancels an assigned order and frees the driver" do
      driver = online_driver(0.5, 100)
      order = assigned_order!()

      assert {:ok, %{status: :cancelled}} = Dispatch.cancel_order(order.id)
      assert {:ok, %{status: :online}} = Tracking.fetch_state(driver.id)
    end

    test "cancels a pending order that has no driver" do
      {:ok, order} = Dispatch.create_order(order_attrs())
      assert {:ok, %{status: :cancelled}} = Dispatch.cancel_order(order.id)
    end

    test "refuses to cancel a delivered order" do
      driver = online_driver(0.5, 100)
      order = assigned_order!()
      {:ok, _} = Dispatch.mark_picked_up(order.id, driver.id)
      {:ok, _} = Dispatch.mark_delivered(order.id, driver.id)

      assert {:error, :invalid_transition} = Dispatch.cancel_order(order.id)
    end
  end
end
