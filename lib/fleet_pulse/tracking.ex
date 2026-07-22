defmodule FleetPulse.Tracking do
  @moduledoc """
  The tracking context — the only public API of the driver-telemetry domain.

  Everything outside this module (channels, LiveViews, the dispatch context)
  talks to this façade. Nothing outside it should reach for `DriverSupervisor`,
  `DriverState`, `DriverRegistry`, `StateCache`, or `Repo` directly: those are
  implementation details of how live state happens to be held today.

  ## Where each piece of state lives

    * position and telemetry — in memory only, flushed periodically by
      `FleetPulse.Tracking.PersistenceBatcher` (PRD 5.2)
    * availability status — written through to PostgreSQL immediately, because
      it is low frequency and must survive a node restart
  """

  import Ecto.Query

  alias FleetPulse.Repo
  alias FleetPulse.Tracking.Driver
  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Tracking.DriverSupervisor
  alias FleetPulse.Tracking.Events
  alias FleetPulse.Tracking.Geo
  alias FleetPulse.Tracking.StateCache
  alias FleetPulse.Tracking.Telemetry
  alias FleetPulse.Types

  @typedoc "A driver and its distance from the query point, in kilometres."
  @type nearby_driver :: {DriverState.t(), float()}

  @typedoc """
  Options for `nearby/3`.

    * `:status` — which availability to accept, or `:any`. Defaults to
      `:online`, because dispatch wants drivers who can take work.
    * `:limit` — keep only the N nearest. Defaults to no limit.
  """
  @type nearby_opts :: [status: Driver.status() | :any, limit: pos_integer()]

  @spec create_driver(map()) :: {:ok, Driver.t()} | {:error, Driver.changeset()}
  def create_driver(attrs) do
    %Driver{}
    |> Driver.changeset(attrs)
    |> Repo.insert()
  end

  @spec fetch_driver(Types.id()) :: {:ok, Driver.t()} | {:error, :not_found}
  def fetch_driver(driver_id) do
    case Repo.get(Driver, driver_id) do
      nil -> {:error, :not_found}
      %Driver{} = driver -> {:ok, driver}
    end
  end

  @spec list_drivers() :: [Driver.t()]
  def list_drivers do
    Driver
    |> order_by([d], asc: d.name)
    |> Repo.all()
  end

  @doc """
  Starts tracking a driver, verifying the driver exists first.

  Idempotent: an already-tracked driver returns its existing process.
  """
  @spec start_tracking(Types.id()) :: {:ok, pid()} | {:error, Types.reason()}
  def start_tracking(driver_id) do
    with {:ok, _driver} <- fetch_driver(driver_id) do
      DriverSupervisor.start_driver(driver_id)
    end
  end

  @spec stop_tracking(Types.id()) :: :ok | {:error, :not_found}
  def stop_tracking(driver_id), do: DriverSupervisor.stop_driver(driver_id)

  @spec track_location(Types.id(), Telemetry.t()) ::
          :ok | {:error, :not_found | :invalid_telemetry}
  def track_location(driver_id, telemetry) do
    DriverState.update_location(driver_id, telemetry)
  end

  @spec fetch_state(Types.id()) :: {:ok, DriverState.t()} | {:error, :not_found}
  def fetch_state(driver_id), do: DriverState.fetch(driver_id)

  @doc """
  Last known state of every cached driver.

  Reads ETS directly, so it costs no message passing and cannot be slowed
  down by a busy driver process — this is what the dispatch dashboard calls
  on mount before subscribing to updates.
  """
  @spec list_tracked() :: [DriverState.t()]
  def list_tracked, do: StateCache.all()

  @doc """
  Drivers within `radius_km` of `coordinates`, nearest first (PRD 5.3).

  Runs entirely in memory: no database round trip and no message sent to any
  driver process, so a busy driver can never slow a dispatch query down.

  The work is done in two passes. `Geo.bounding_box/2` discards the vast
  majority with four float comparisons and no trigonometry; only the survivors
  pay for `Geo.distance_km/2`. The box is deliberately never too small, so the
  second pass is what actually decides membership.
  """
  @spec nearby(Types.coordinates(), float(), nearby_opts()) :: [nearby_driver()]
  def nearby(coordinates, radius_km, opts \\ []) do
    status = Keyword.get(opts, :status, :online)
    box = Geo.bounding_box(coordinates, radius_km)

    StateCache.all()
    |> Enum.filter(&candidate?(&1, status, box))
    |> Enum.map(&{&1, Geo.distance_km(coordinates, &1.coordinates)})
    |> Enum.filter(fn {_state, distance} -> distance <= radius_km end)
    |> Enum.sort_by(fn {_state, distance} -> distance end)
    |> take(Keyword.get(opts, :limit))
  end

  @doc """
  Sets a driver's availability, writing through to the database.

  The database write comes first and is authoritative: a driver marked
  `:busy` mid-order must still be `:busy` after a node restart, and the
  location batcher never touches the status column. Updating the live process
  afterwards is best effort — a driver with no running process is a normal
  situation, not a failure.
  """
  @spec set_status(Types.id(), Driver.status()) ::
          {:ok, Driver.t()} | {:error, :not_found | Driver.changeset()}
  def set_status(driver_id, status) do
    with {:ok, driver} <- fetch_driver(driver_id),
         {:ok, updated} <- persist_status(driver, status) do
      _ = DriverState.update_status(driver_id, status)
      {:ok, updated}
    end
  end

  @spec persist_status(Driver.t(), Driver.status()) ::
          {:ok, Driver.t()} | {:error, Driver.changeset()}
  defp persist_status(driver, status) do
    driver
    |> Driver.status_changeset(%{status: status})
    |> Repo.update()
  end

  @spec subscribe_fleet() :: Events.subscribe_result()
  def subscribe_fleet, do: Events.subscribe_fleet()

  @spec subscribe_driver(Types.id()) :: Events.subscribe_result()
  def subscribe_driver(driver_id), do: Events.subscribe_driver(driver_id)

  @spec unsubscribe_fleet() :: :ok
  def unsubscribe_fleet, do: Events.unsubscribe_fleet()

  @spec unsubscribe_driver(Types.id()) :: :ok
  def unsubscribe_driver(driver_id), do: Events.unsubscribe_driver(driver_id)

  @spec candidate?(DriverState.t(), Driver.status() | :any, Geo.box()) :: boolean()
  defp candidate?(%DriverState{coordinates: nil}, _status, _box), do: false

  defp candidate?(%DriverState{coordinates: coordinates, status: actual}, wanted, box) do
    status_matches?(actual, wanted) and Geo.within_box?(coordinates, box)
  end

  @spec status_matches?(Driver.status(), Driver.status() | :any) :: boolean()
  defp status_matches?(_actual, :any), do: true
  defp status_matches?(status, status), do: true
  defp status_matches?(_actual, _wanted), do: false

  @spec take([nearby_driver()], pos_integer() | nil) :: [nearby_driver()]
  defp take(drivers, nil), do: drivers
  defp take(drivers, count), do: Enum.take(drivers, count)
end
