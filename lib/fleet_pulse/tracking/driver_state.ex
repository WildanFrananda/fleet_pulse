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
  alias FleetPulse.Tracking.Events
  alias FleetPulse.Tracking.Snapshot
  alias FleetPulse.Tracking.StateCache
  alias FleetPulse.Tracking.Telemetry
  alias FleetPulse.Types

  @typedoc """
  A driver's live state.

  `recorded_at` is the device clock (when the GPS fix was taken).
  `synced_at` is the server clock: when this state was last committed to the
  cache, whether by a ping, a status change, or rehydration. It is what the
  idle reaper measures staleness against, so every cached state must carry
  one — which is why `commit/1` stamps it rather than the individual casts.

  `capacity_kg` is a COPY of the drivers table, taken at rehydration. It goes
  stale if the record changes while the driver is tracked — acceptable because
  a vehicle's payload changes far more rarely than a driver reconnects, and
  the alternative is a database read on every dispatch query.
  """
  @type t :: %__MODULE__{
          driver_id: Types.id(),
          capacity_kg: non_neg_integer(),
          status: Driver.status(),
          coordinates: Types.coordinates() | nil,
          speed_kmh: float() | nil,
          bearing_deg: float() | nil,
          recorded_at: DateTime.t() | nil,
          synced_at: DateTime.t() | nil
        }

  @enforce_keys [:driver_id]
  defstruct [
    :driver_id,
    :coordinates,
    :speed_kmh,
    :bearing_deg,
    :recorded_at,
    :synced_at,
    capacity_kg: 0,
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
      {:ok, pid} -> safe_fetch(pid)
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Writes a new position.

  The payload is validated and normalised in the CALLING process, before
  anything reaches the mailbox — the same discipline `update_status/2` uses.
  """
  @spec update_location(Types.id(), Telemetry.t()) ::
          :ok | {:error, :not_found | :invalid_telemetry}
  def update_location(driver_id, telemetry) do
    with {:ok, telemetry} <- Telemetry.normalise(telemetry),
         {:ok, pid} <- DriverRegistry.whereis(driver_id) do
      GenServer.cast(pid, {:update_location, telemetry})
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

  @doc """
  Atomically claims a driver for work.

  Succeeds only if the driver is currently `:online`, flipping it to `:busy`
  in the same, indivisible message. Two concurrent claims for the same driver
  are serialised by the process: exactly one sees `:online` and wins; the
  other sees `:busy` and loses. This is what prevents two orders from being
  assigned the same driver, with no lock and no transaction.
  """
  @spec claim(Types.id()) :: {:ok, t()} | {:error, :not_found | :unavailable}
  def claim(driver_id) do
    case DriverRegistry.whereis(driver_id) do
      {:ok, pid} -> safe_claim(pid)
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Releases a claimed driver back to `:online`.

  Used when an assignment is rolled back — the order failed to persist after
  the driver was claimed. A no-op unless the driver is currently `:busy`.
  """
  @spec release(Types.id()) :: :ok | {:error, :not_found}
  def release(driver_id) do
    case DriverRegistry.whereis(driver_id) do
      {:ok, pid} -> GenServer.cast(pid, :release)
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Whether a state counts as idle: marked offline, and untouched since `cutoff`.

  Public because both the reaper's cheap ETS-side filter and the process's own
  authoritative check must apply the SAME rule.
  """
  @spec idle?(t(), DateTime.t()) :: boolean()
  def idle?(%__MODULE__{status: :offline, synced_at: %DateTime{} = synced_at}, cutoff) do
    DateTime.before?(synced_at, cutoff)
  end

  def idle?(_state, _cutoff), do: false

  @doc """
  Stops the driver if it is idle as of `cutoff`.

  The decision is made INSIDE the process, against its own current state, so a
  driver that reconnects between the reaper's scan and this call is never
  killed on a stale reading.
  """
  @spec stop_if_idle(Types.id(), DateTime.t()) :: :stopped | :active | {:error, :not_found}
  def stop_if_idle(driver_id, cutoff) do
    case DriverRegistry.whereis(driver_id) do
      {:ok, pid} -> safe_stop_if_idle(pid, cutoff)
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
        {:noreply, commit(cached)}

      {:error, :not_found} ->
        case Snapshot.fetch(driver_id) do
          {:ok, snapshot} -> {:noreply, commit(apply_snapshot(state, snapshot))}
          {:error, :not_found} -> {:stop, {:shutdown, :unknown_driver}, state}
        end
    end
  end

  @impl GenServer
  @spec handle_call(:fetch | :claim | {:stop_if_idle, DateTime.t()}, GenServer.from(), t()) ::
          {:reply, t() | :active | {:ok, t()} | {:error, :unavailable}, t()}
          | {:stop, {:shutdown, :idle}, :stopped, t()}
  def handle_call(:fetch, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:claim, _from, %__MODULE__{status: :online} = state) do
    claimed = commit(%{state | status: :busy})
    {:reply, {:ok, claimed}, claimed}
  end

  def handle_call(:claim, _from, state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call({:stop_if_idle, cutoff}, _from, state) do
    idle_reply(idle?(state, cutoff), state)
  end

  @impl GenServer
  @spec handle_cast(
          {:update_location, Telemetry.t()} | {:update_status, Driver.status()} | :release,
          t()
        ) :: {:noreply, t()}
  def handle_cast({:update_location, telemetry}, state) do
    {:noreply,
     commit(%{
       state
       | coordinates: {telemetry.latitude, telemetry.longitude},
         speed_kmh: Map.get(telemetry, :speed_kmh),
         bearing_deg: Map.get(telemetry, :bearing_deg),
         recorded_at: telemetry.recorded_at
     })}
  end

  def handle_cast({:update_status, status}, state) do
    {:noreply, commit(%{state | status: status})}
  end

  def handle_cast(:release, %__MODULE__{status: :busy} = state) do
    {:noreply, commit(%{state | status: :online})}
  end

  def handle_cast(:release, state) do
    {:noreply, state}
  end

  @impl GenServer
  @spec terminate(term(), t()) :: :ok
  def terminate(:normal, %__MODULE__{driver_id: driver_id}), do: evict(driver_id)
  def terminate(:shutdown, %__MODULE__{driver_id: driver_id}), do: evict(driver_id)

  def terminate({:shutdown, _reason}, %__MODULE__{driver_id: driver_id}), do: evict(driver_id)

  def terminate(_crash_reason, _state), do: :ok

  @spec evict(Types.id()) :: :ok
  defp evict(driver_id) do
    :ok = StateCache.delete(driver_id)
    Events.broadcast(driver_id, {:driver_stopped, driver_id})
  end

  @spec commit(t()) :: t()
  defp commit(%__MODULE__{} = state) do
    stamped = %{state | synced_at: DateTime.utc_now()}
    :ok = StateCache.put(state.driver_id, stamped)
    :ok = Events.broadcast(stamped.driver_id, {:driver_updated, stamped})
    stamped
  end

  @spec apply_snapshot(t(), Snapshot.t()) :: t()
  defp apply_snapshot(%__MODULE__{} = state, snapshot) do
    %{
      state
      | status: snapshot.status,
        capacity_kg: snapshot.capacity_kg,
        coordinates: snapshot.coordinates,
        speed_kmh: snapshot.speed_kmh,
        bearing_deg: snapshot.bearing_deg,
        recorded_at: snapshot.recorded_at
    }
  end

  @spec idle_reply(boolean(), t()) ::
          {:reply, :active, t()} | {:stop, {:shutdown, :idle}, :stopped, t()}
  defp idle_reply(false, state), do: {:reply, :active, state}
  defp idle_reply(true, state), do: {:stop, {:shutdown, :idle}, :stopped, state}

  @spec safe_fetch(pid()) :: {:ok, t()} | {:error, :not_found}
  defp safe_fetch(pid) do
    {:ok, GenServer.call(pid, :fetch)}
  catch
    :exit, _reason -> {:error, :not_found}
  end

  @spec safe_claim(pid()) :: {:ok, t()} | {:error, :not_found | :unavailable}
  defp safe_claim(pid) do
    GenServer.call(pid, :claim)
  catch
    :exit, _reason -> {:error, :not_found}
  end

  @spec safe_stop_if_idle(pid(), DateTime.t()) :: :stopped | :active | {:error, :not_found}
  defp safe_stop_if_idle(pid, cutoff) do
    GenServer.call(pid, {:stop_if_idle, cutoff})
  catch
    :exit, _reason -> {:error, :not_found}
  end
end
