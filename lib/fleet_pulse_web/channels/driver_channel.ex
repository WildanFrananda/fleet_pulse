defmodule FleetPulseWeb.DriverChannel do
  @moduledoc """
  Telemetry ingress for one driver (PRD 5.1).

  Thin by design: it parses the wire format, checks authorisation, and hands
  everything else to `FleetPulse.Tracking`. No business rules live here.

  ## Disconnect policy

  When the channel dies the driver is marked `:offline`, but its
  `DriverState` process is deliberately LEFT RUNNING. Mobile connections drop
  constantly — tunnels, cell handovers, screen locks — and a reconnect seconds
  later should not have to re-read Postgres and lose whatever position had not
  been flushed yet.

  KNOWN DEBT: nothing reaps a process whose driver never comes back. Those
  processes keep their cache entry, so the batcher re-persists their stale
  position every interval, forever. An idle reaper (stop any driver with no
  update for N minutes) is required before this runs at PRD scale.
  """

  use FleetPulseWeb, :channel

  alias FleetPulse.Dispatch
  alias FleetPulse.Dispatch.Events
  alias FleetPulse.Dispatch.Order
  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.Driver
  alias FleetPulse.Tracking.Telemetry
  alias FleetPulse.Types

  @typedoc "An order serialised for the wire — the shape pushed to a device."
  @type order_wire :: %{
          id: term(),
          status: term(),
          weight_kg: term(),
          pickup: %{latitude: term(), longitude: term()},
          dropoff: %{latitude: term(), longitude: term()},
          assigned_at: term()
        }

  @typedoc """
  Every failure that can reach a driver's device from this channel.

  Enumerated rather than left as `term()` so that adding a new error path in
  the context makes Dialyzer point here, instead of the new case silently
  collapsing into the `"unprocessable"` catch-all.
  """
  @type error ::
          :forbidden
          | :invalid_status
          | :invalid_telemetry
          | :invalid_topic
          | :not_found
          | {:start_failed, term()}
          | Driver.changeset()

  @impl Phoenix.Channel
  @spec join(String.t(), map(), Phoenix.Socket.t()) ::
          {:ok, Phoenix.Socket.t()} | {:error, %{reason: String.t()}}
  def join("driver:" <> topic_id, _payload, socket) do
    with {:ok, driver_id} <- parse_id(topic_id),
         :ok <- authorise(driver_id, socket.assigns.driver_id),
         {:ok, _pid} <- Tracking.start_tracking(driver_id),
         {:ok, _driver} <- Tracking.set_status(driver_id, join_status(driver_id)) do
      :ok = Events.subscribe_driver(driver_id)
      send(self(), :after_join)
      {:ok, assign(socket, :tracking, driver_id)}
    else
      {:error, reason} -> {:error, %{reason: to_reason(reason)}}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "unknown_topic"}}

  @impl Phoenix.Channel
  @spec handle_in(String.t(), map(), Phoenix.Socket.t()) ::
          {:reply, :ok | {:error, %{reason: String.t()}}, Phoenix.Socket.t()}
          | {:noreply, Phoenix.Socket.t()}

  def handle_in("ping", params, socket) do
    driver_id = socket.assigns.driver_id

    with {:ok, telemetry} <- Telemetry.from_params(params),
         :ok <- Tracking.track_location(driver_id, telemetry) do
      {:reply, :ok, socket}
    else
      {:error, reason} -> {:reply, {:error, %{reason: to_reason(reason)}}, socket}
    end
  end

  def handle_in("status", %{"status" => status}, socket) do
    driver_id = socket.assigns.driver_id

    with {:ok, parsed} <- parse_status(status),
         {:ok, _driver} <- Tracking.set_status(driver_id, parsed) do
      {:reply, :ok, socket}
    else
      {:error, reason} -> {:reply, {:error, %{reason: to_reason(reason)}}, socket}
    end
  end

  def handle_in("pickup", %{"order_id" => order_id}, socket) when is_integer(order_id) do
    reply_transition(Dispatch.mark_picked_up(order_id, socket.assigns.driver_id), socket)
  end

  def handle_in("delivered", %{"order_id" => order_id}, socket) when is_integer(order_id) do
    reply_transition(Dispatch.mark_delivered(order_id, socket.assigns.driver_id), socket)
  end

  def handle_in(_event, _params, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  @impl Phoenix.Channel
  @spec handle_info(term(), Phoenix.Socket.t()) :: {:noreply, Phoenix.Socket.t()}
  def handle_info(:after_join, socket) do
    push(socket, "active_order", active_order_payload(socket.assigns.driver_id))
    {:noreply, socket}
  end

  def handle_info({:order_assigned, %Order{} = order}, socket) do
    push(socket, "order_assigned", order_payload(order))
    {:noreply, socket}
  end

  def handle_info({:order_updated, %Order{} = order}, socket) do
    push(socket, "order_updated", order_payload(order))
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.Channel
  @spec terminate(term(), Phoenix.Socket.t()) :: :ok
  def terminate(_reason, %Phoenix.Socket{assigns: %{tracking: driver_id}}) do
    _ = Tracking.set_status(driver_id, :offline)
    :ok
  end

  def terminate(_reason, _socket), do: :ok

  @spec authorise(Types.id(), Types.id()) :: :ok | {:error, :forbidden}
  defp authorise(driver_id, driver_id), do: :ok
  defp authorise(_topic_id, _authenticated_id), do: {:error, :forbidden}

  @spec parse_id(String.t()) :: {:ok, Types.id()} | {:error, :invalid_topic}
  defp parse_id(topic_id) do
    case Integer.parse(topic_id) do
      {driver_id, ""} when driver_id > 0 -> {:ok, driver_id}
      _invalid -> {:error, :invalid_topic}
    end
  end

  @spec parse_status(term()) :: {:ok, Driver.status()} | {:error, :invalid_status}
  defp parse_status(status) when is_binary(status) do
    case Enum.find(Driver.statuses(), &(Atom.to_string(&1) == status)) do
      nil -> {:error, :invalid_status}
      known -> {:ok, known}
    end
  end

  defp parse_status(_status), do: {:error, :invalid_status}

  @spec to_reason(error()) :: String.t()
  defp to_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp to_reason(_reason), do: "unprocessable"

  @spec reply_transition({:ok, Order.t()} | {:error, atom()}, Phoenix.Socket.t()) ::
          {:reply, :ok | {:error, %{reason: String.t()}}, Phoenix.Socket.t()}
  defp reply_transition({:ok, %Order{}}, socket), do: {:reply, :ok, socket}

  defp reply_transition({:error, reason}, socket) do
    {:reply, {:error, %{reason: to_reason(reason)}}, socket}
  end

  @spec join_status(Types.id()) :: :online | :busy
  defp join_status(driver_id) do
    status_for(Dispatch.active_order_for_driver(driver_id))
  end

  @spec status_for(Order.t() | nil) :: :online | :busy
  defp status_for(nil), do: :online
  defp status_for(%Order{}), do: :busy

  @spec active_order_payload(Types.id()) :: %{order: order_wire() | nil}
  defp active_order_payload(driver_id) do
    order_or_nil(Dispatch.active_order_for_driver(driver_id))
  end

  @spec order_or_nil(Order.t() | nil) :: %{order: order_wire() | nil}
  defp order_or_nil(nil), do: %{order: nil}
  defp order_or_nil(%Order{} = order), do: %{order: order_payload(order)}

  @spec order_payload(Order.t()) :: map()
  defp order_payload(%Order{} = order) do
    %{
      id: order.id,
      status: order.status,
      weight_kg: order.weight_kg,
      pickup: %{latitude: order.pickup_latitude, longitude: order.pickup_longitude},
      dropoff: %{latitude: order.dropoff_latitude, longitude: order.dropoff_longitude},
      assigned_at: order.assigned_at
    }
  end
end
