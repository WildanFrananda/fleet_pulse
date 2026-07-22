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

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.Driver
  alias FleetPulse.Tracking.Telemetry
  alias FleetPulse.Types

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
         {:ok, _driver} <- Tracking.set_status(driver_id, :online) do
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

  def handle_in(_event, _params, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

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
end
