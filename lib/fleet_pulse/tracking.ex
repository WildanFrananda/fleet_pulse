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
  alias FleetPulse.Tracking.StateCache
  alias FleetPulse.Tracking.Telemetry
  alias FleetPulse.Types

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
end
