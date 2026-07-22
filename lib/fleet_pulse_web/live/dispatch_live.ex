defmodule FleetPulseWeb.DispatchLive do
  @moduledoc """
  The dispatcher's live fleet view (PRD 5.4).

  Reads the current fleet from ETS once at mount, then keeps itself current
  from PubSub. Nothing polls, and no database query runs after mount.

  ## Why updates are buffered

  At the PRD's fleet size the `"tracking:fleet"` topic carries roughly 2000
  messages per second. Assigning on every one of them would mean 2000 renders
  and 2000 DOM patches per second — work no human eye can consume.

  So updates accumulate in `:pending`, a map keyed by driver_id, and are
  merged into `:drivers` on a timer. The map is doing two jobs: it caps the
  render rate, and it DEDUPLICATES. A driver that pings ten times between two
  flushes collapses into a single entry holding its latest position. A list
  would only delay the same 2000 updates, not reduce them.
  """

  use FleetPulseWeb, :live_view

  alias FleetPulse.Tracking
  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Types
  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  @default_flush_interval_ms 500

  @typedoc "Drivers indexed by id, the shape both `:drivers` and `:pending` hold."
  @type index :: %{Types.id() => DriverState.t()}

  @impl Phoenix.LiveView
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, start(connected?(socket), socket)}
  end

  @impl Phoenix.LiveView
  @spec handle_info(
          {:driver_updated, DriverState.t()} | {:driver_stopper, Types.id()} | :flush,
          Socket.t()
        ) :: {:noreply, Socket.t()}
  def handle_info({:driver_updated, state}, socket) do
    {:noreply, update(socket, :pending, &Map.put(&1, state.driver_id, state))}
  end

  def handle_info({:driver_stopped, driver_id}, socket) do
    {:noreply,
     socket
     |> update(:drivers, &Map.delete(&1, driver_id))
     |> update(:pending, &Map.delete(&1, driver_id))}
  end

  def handle_info(:flush, socket) do
    _timer = schedule_flush()
    {:noreply, flush(socket)}
  end

  @impl Phoenix.LiveView
  @spec render(map()) :: Rendered.t()
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Dispatch
        <:subtitle>{map_size(@drivers)} driver(s) tracked</:subtitle>
      </.header>

      <.table id="drivers" rows={rows(@drivers)}>
        <:col :let={driver} label="Driver">{driver.driver_id}</:col>
        <:col :let={driver} label="Status">{driver.status}</:col>
        <:col :let={driver} label="Position">{position(driver.coordinates)}</:col>
        <:col :let={driver} label="Speed">{speed(driver.speed_kmh)}</:col>
        <:col :let={driver} label="Last seen">{seen(driver.synced_at)}</:col>
      </.table>
    </Layouts.app>
    """
  end

  @spec start(boolean(), Socket.t()) :: Socket.t()
  defp start(true, socket) do
    :ok = Tracking.subscribe_fleet()
    _timer = schedule_flush()
    assign_fleet(socket)
  end

  defp start(false, socket), do: assign_fleet(socket)

  @spec assign_fleet(Socket.t()) :: Socket.t()
  defp assign_fleet(socket) do
    drivers = Map.new(Tracking.list_tracked(), &{&1.driver_id, &1})

    socket
    |> assign(:drivers, drivers)
    |> assign(:pending, %{})
  end

  @spec flush(Socket.t()) :: Socket.t()
  defp flush(socket) do
    merge_pending(map_size(socket.assigns.pending), socket)
  end

  @spec merge_pending(non_neg_integer(), Socket.t()) :: Socket.t()
  defp merge_pending(0, socket), do: socket

  defp merge_pending(_count, socket) do
    socket
    |> update(:drivers, &Map.merge(&1, socket.assigns.pending))
    |> assign(:pending, %{})
  end

  @spec schedule_flush() :: reference()
  defp schedule_flush do
    Process.send_after(self(), :flush, flush_interval_ms())
  end

  @spec flush_interval_ms() :: pos_integer()
  defp flush_interval_ms do
    :fleet_pulse
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:flush_interval_ms)
    |> interval_or_default()
  end

  @spec interval_or_default(term()) :: pos_integer()
  defp interval_or_default(value) when is_integer(value) and value > 0, do: value
  defp interval_or_default(_value), do: @default_flush_interval_ms

  @spec rows(index()) :: [DriverState.t()]
  defp rows(drivers) do
    drivers |> Map.values() |> Enum.sort_by(& &1.driver_id)
  end

  @spec position(Types.coordinates() | nil) :: String.t()
  defp position(nil), do: "—"
  defp position({lat, lng}), do: "#{Float.round(lat, 5)}, #{Float.round(lng, 5)}"

  @spec speed(float() | nil) :: String.t()
  defp speed(nil), do: "—"
  defp speed(kmh), do: "#{Float.round(kmh, 1)} km/h"

  @spec seen(DateTime.t() | nil) :: String.t()
  defp seen(nil), do: "—"
  defp seen(at), do: Calendar.strftime(at, "%H:%M:%S")
end
