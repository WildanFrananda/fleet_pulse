defmodule FleetPulse.Tracking.DriverState do
  @moduledoc """
  GenServer process holding ONE driver's live state in memory (PRD 5.2).

  This is why FleetPulse does not hit the database every three seconds: a
  location update only rewrites a map inside this process. Persistence happens
  separately and in batches.

  `restart: :transient` — a process that stops normally (driver logged out) is
  NOT restarted. Only crashes trigger a restart.
  """

  use GenServer, restart: :transient

  alias FleetPulse.Tracking.Driver
  alias FleetPulse.Tracking.DriverRegistry
  alias FleetPulse.Tracking.Snapshot
  alias FleetPulse.Tracking.StateCache
  alias FleetPulse.Types

  @typedoc """
  A driver's live state.

  `recorded_at` is the device clock (when the GPS fix was taken).
  `synced_at` is the server clock (when we received it).
  The gap between them exposes clock skew and delayed connections.
  """
  @type t :: %__MODULE__{
          driver_id: Types.id(),
          status: Driver.status(),
          coordinates: Types.coordinates() | nil,
          speed_kmh: float() | nil,
          bearing_deg: float() | nil,
          recorded_at: DateTime.t() | nil,
          synced_at: DateTime.t() | nil
        }

  @typedoc """
  An already-validated telemetry payload coming from the channel.

  `required`/`optional` make the map's shape explicit — the closest Elixir
  equivalent of a TypeScript `interface` for maps.
  """
  @type telemetry :: %{
          required(:latitude) => Types.latitude(),
          required(:longitude) => Types.longitude(),
          required(:recorded_at) => DateTime.t(),
          optional(:speed_kmh) => float() | nil,
          optional(:bearing_deg) => float() | nil
        }

  @enforce_keys [:driver_id]
  defstruct [
    :driver_id,
    :coordinates,
    :speed_kmh,
    :bearing_deg,
    :recorded_at,
    :synced_at,
    status: :offline
  ]

  @spec start_link(Types.id()) :: GenServer.on_start()
  def start_link(driver_id) when is_integer(driver_id) and driver_id > 0 do
    GenServer.start_link(__MODULE__, driver_id, name: DriverRegistry.via(driver_id))
  end

  @doc """
  Reads a snapshot of a driver's live state.
  """
  @spec fetch(Types.id()) :: {:ok, t()} | {:error, :not_found}
  def fetch(driver_id) do
    case DriverRegistry.whereis(driver_id) do
      {:ok, pid} -> {:ok, GenServer.call(pid, :fetch)}
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Writes a new position.

  Telemetry is validated and normalised HERE, in the calling process, before
  anything reaches the mailbox — the same discipline `update_status/2` uses.
  This is the single choke point protecting the cache: `Repo.insert_all/3`
  bypasses changesets entirely, so a bad value that reaches ETS would later
  crash the persistence batcher on every retry, forever.
  """
  @spec update_location(Types.id(), telemetry()) ::
          :ok | {:error, :not_found | :invalid_telemetry}
  def update_location(driver_id, telemetry) do
    with {:ok, normalised} <- normalise(telemetry),
         {:ok, pid} <- DriverRegistry.whereis(driver_id) do
      GenServer.cast(pid, {:update_location, normalised})
    end
  end

  @doc """
  Changes the availability status.

  The status is validated HERE, in the calling process, not inside the
  GenServer. That way an invalid value never reaches the mailbox, and we can
  return `{:error, _}` instead of raising.
  """
  @spec update_status(Types.id(), Driver.status()) :: :ok | {:error, :not_found | :invalid_status}
  def update_status(driver_id, status) do
    with true <- status in Driver.statuses(), {:ok, pid} <- DriverRegistry.whereis(driver_id) do
      GenServer.cast(pid, {:update_status, status})
    else
      false -> {:error, :invalid_status}
      {:error, :not_found} = error -> error
    end
  end

  @impl GenServer
  @spec init(Types.id()) :: {:ok, t(), {:continue, :rehydrate}}
  def init(driver_id) do
    Process.flag(:trap_exit, true)

    {:ok, %__MODULE__{driver_id: driver_id}, {:continue, :rehydrate}}
  end

  @impl GenServer
  @spec handle_continue(:rehydrate, t()) ::
          {:noreply, t()} | {:stop, {:shutdown, :unknown_driver}, t()}
  def handle_continue(:rehydrate, %__MODULE__{driver_id: driver_id} = state) do
    case StateCache.fetch(driver_id) do
      {:ok, cached} ->
        {:noreply, cached}

      {:error, :not_found} ->
        case Snapshot.fetch(driver_id) do
          {:ok, snapshot} -> {:noreply, apply_snapshot(state, snapshot)}
          {:error, :not_found} -> {:stop, {:shutdown, :unknown_driver}, state}
        end
    end
  end

  @impl GenServer
  @spec handle_call(:fetch, GenServer.from(), t()) :: {:reply, t(), t()}
  def handle_call(:fetch, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  @spec handle_cast({:update_location, telemetry()} | {:update_status, Driver.status()}, t()) ::
          {:noreply, t()}
  def handle_cast({:update_location, telemetry}, state) do
    {:noreply,
     commit(%{
       state
       | coordinates: {telemetry.latitude, telemetry.longitude},
         speed_kmh: Map.get(telemetry, :speed_kmh),
         bearing_deg: Map.get(telemetry, :bearing_deg),
         recorded_at: telemetry.recorded_at,
         synced_at: DateTime.utc_now()
     })}
  end

  def handle_cast({:update_status, status}, state) do
    {:noreply, commit(%{state | status: status, synced_at: DateTime.utc_now()})}
  end

  @impl GenServer
  @spec terminate(term(), t()) :: :ok
  def terminate(:normal, %__MODULE__{driver_id: driver_id}), do: StateCache.delete(driver_id)
  def terminate(:shutdown, %__MODULE__{driver_id: driver_id}), do: StateCache.delete(driver_id)

  def terminate({:shutdown, _reason}, %__MODULE__{driver_id: driver_id}),
    do: StateCache.delete(driver_id)

  def terminate(_crash_reason, _state), do: :ok

  @spec commit(t()) :: t()
  defp commit(%__MODULE__{} = state) do
    :ok = StateCache.put(state.driver_id, state)
    state
  end

  @spec apply_snapshot(t(), Snapshot.t()) :: t()
  defp apply_snapshot(%__MODULE__{} = state, snapshot) do
    %{
      state
      | status: snapshot.status,
        coordinates: snapshot.coordinates,
        speed_kmh: snapshot.speed_kmh,
        bearing_deg: snapshot.bearing_deg,
        recorded_at: snapshot.recorded_at
    }
  end

  @spec normalise(term()) :: {:ok, telemetry()} | {:error, :invalid_telemetry}
  defp normalise(%{recorded_at: %DateTime{} = recorded_at} = telemetry) do
    with {:ok, lat} <- validate_latitude(Map.get(telemetry, :latitude)),
         {:ok, lng} <- validate_longitude(Map.get(telemetry, :longitude)),
         {:ok, speed} <- validate_speed(Map.get(telemetry, :speed_kmh)),
         {:ok, bearing} <- validate_bearing(Map.get(telemetry, :bearing_deg)) do
      {:ok,
       %{
         latitude: lat,
         longitude: lng,
         speed_kmh: speed,
         bearing_deg: bearing,
         recorded_at: with_usec(recorded_at)
       }}
    end
  end

  defp normalise(_telemetry), do: {:error, :invalid_telemetry}

  @spec validate_latitude(term()) :: {:ok, Types.latitude()} | {:error, :invalid_telemetry}
  defp validate_latitude(lat) when is_number(lat) and lat >= -90 and lat <= 90,
    do: {:ok, lat * 1.0}

  defp validate_latitude(_lat), do: {:error, :invalid_telemetry}

  @spec validate_longitude(term()) :: {:ok, Types.longitude()} | {:error, :invalid_telemetry}
  defp validate_longitude(lng) when is_number(lng) and lng >= -180 and lng <= 180,
    do: {:ok, lng * 1.0}

  defp validate_longitude(_lng), do: {:error, :invalid_telemetry}

  @spec validate_speed(term()) :: {:ok, float() | nil} | {:error, :invalid_telemetry}
  defp validate_speed(nil), do: {:ok, nil}
  defp validate_speed(speed) when is_number(speed) and speed >= 0, do: {:ok, speed * 1.0}
  defp validate_speed(_speed), do: {:error, :invalid_telemetry}

  @spec validate_bearing(term()) :: {:ok, float() | nil} | {:error, :invalid_telemetry}
  defp validate_bearing(nil), do: {:ok, nil}

  defp validate_bearing(bearing) when is_number(bearing) and bearing >= 0 and bearing < 360,
    do: {:ok, bearing * 1.0}

  defp validate_bearing(_bearing), do: {:error, :invalid_telemetry}

  @spec with_usec(DateTime.t()) :: DateTime.t()
  defp with_usec(%DateTime{microsecond: {_value, 6}} = recorded_at), do: recorded_at

  defp with_usec(%DateTime{microsecond: {value, _precision}} = recorded_at),
    do: %{recorded_at | microsecond: {value, 6}}
end
