defmodule FleetPulse.Dispatch do
  @moduledoc """
  The dispatch context — order intake and driver assignment (PRD 5.5).

  Assignment is the delicate part. Choosing a driver is a read of in-memory
  state, and between that read and the write that assigns them, another
  dispatcher could choose the same driver. The claim closes that window: it is
  an atomic flip performed inside the driver's own process, and only after it
  succeeds is the order persisted.

  If persistence then fails, the claim is released, so a driver is never left
  marked busy for an order that does not exist.
  """

  import Ecto.Query

  alias FleetPulse.Dispatch.Events
  alias FleetPulse.Dispatch.Order
  alias FleetPulse.Repo
  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Types

  @typedoc "Why an order could not be assigned to any driver."
  @type assign_error :: :no_driver_available | :not_found | :already_assigned

  @spec create_order(map()) :: {:ok, Order.t()} | {:error, Order.changeset()}
  def create_order(attrs) do
    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert()
  end

  @spec fetch_order(Types.id()) :: {:ok, Order.t()} | {:error, :not_found}
  def fetch_order(order_id) do
    case Repo.get(Order, order_id) do
      nil -> {:error, :not_found}
      %Order{} = order -> {:ok, order}
    end
  end

  @spec list_pending_orders() :: [Order.t()]
  def list_pending_orders do
    Order
    |> where([o], o.status == :pending)
    |> order_by([o], asc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Assigns a pending order to the nearest eligible driver.

  Eligible means online, within `radius_km` of the pickup, and able to carry
  the order's weight. The nearest such driver is claimed atomically before the
  order is written; if two orders race for the same driver, only one claim
  succeeds and the loser moves to the next candidate.
  """
  @spec assign_order(Types.id(), float()) ::
          {:ok, Order.t()} | {:error, assign_error() | Order.changeset()}
  def assign_order(order_id, radius_km \\ 3.0) do
    with {:ok, order} <- fetch_order(order_id),
         :ok <- ensure_pending(order),
         {:ok, driver_state} <- claim_nearest(order, radius_km) do
      persist_assignment(order, driver_state)
    end
  end

  @spec ensure_pending(Order.t()) :: :ok | {:error, :already_assigned}
  defp ensure_pending(%Order{status: :pending}), do: :ok
  defp ensure_pending(%Order{}), do: {:error, :already_assigned}

  @spec claim_nearest(Order.t(), float()) ::
          {:ok, DriverState.t()} | {:error, :no_driver_available}
  defp claim_nearest(order, radius_km) do
    order
    |> eligible_drivers(radius_km)
    |> first_successful_claim()
  end

  @spec eligible_drivers(Order.t(), float()) :: [DriverState.t()]
  defp eligible_drivers(order, radius_km) do
    Tracking.nearby(
      {order.pickup_latitude, order.pickup_longitude},
      radius_km,
      status: :online,
      min_capacity_kg: order.weight_kg
    )
    |> Enum.map(fn {state, _distance} -> state end)
  end

  @spec first_successful_claim([DriverState.t()]) ::
          {:ok, DriverState.t()} | {:error, :no_driver_available}
  defp first_successful_claim([]), do: {:error, :no_driver_available}

  defp first_successful_claim([candidate | rest]) do
    case DriverState.claim(candidate.driver_id) do
      {:ok, claimed} -> {:ok, claimed}
      {:error, _reason} -> first_successful_claim(rest)
    end
  end

  @spec persist_assignment(Order.t(), DriverState.t()) ::
          {:ok, Order.t()} | {:error, Order.changeset()}
  defp persist_assignment(order, driver_state) do
    order
    |> Ecto.Changeset.change(
      status: :assigned,
      driver_id: driver_state.driver_id,
      assigned_at: DateTime.utc_now()
    )
    |> Repo.update()
    |> release_on_failure(driver_state.driver_id)
    |> broadcast_on_success(driver_state.driver_id)
  end

  @spec broadcast_on_success(
          {:ok, Order.t()} | {:error, Order.changeset()},
          Types.id()
        ) :: {:ok, Order.t()} | {:error, Order.changeset()}
  defp broadcast_on_success({:ok, order} = ok, driver_id) do
    :ok = Events.broadcast(driver_id, {:order_assigned, order})
    ok
  end

  defp broadcast_on_success({:error, _changeset} = error, _driver_id), do: error

  @spec release_on_failure(
          {:ok, Order.t()} | {:error, Order.changeset()},
          Types.id()
        ) :: {:ok, Order.t()} | {:error, Order.changeset()}
  defp release_on_failure({:ok, _order} = ok, _driver_id), do: ok

  defp release_on_failure({:error, _changeset} = error, driver_id) do
    _ = DriverState.release(driver_id)
    error
  end
end
