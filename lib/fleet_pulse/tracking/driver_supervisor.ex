defmodule FleetPulse.Tracking.DriverSupervisor do
  @moduledoc """
  DynamicSupervisor that starts one `DriverState` process per driver, on
  demand — typically when a driver connects through the telemetry channel.
  """

  use DynamicSupervisor

  alias FleetPulse.Tracking.DriverRegistry
  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Types

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  @spec init(keyword()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a driver process, or returns the existing one.

  Idempotent: calling this twice for the same driver is NOT an error. That
  matters because a client may reconnect before its previous process has
  finished shutting down.
  """
  @spec start_driver(Types.id()) :: {:ok, pid()} | {:error, Types.reason()}
  def start_driver(driver_id) do
    case DynamicSupervisor.start_child(__MODULE__, {DriverState, driver_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, {:start_failed, reason}}
    end
  end

  @doc """
  Shuts a driver process down normally.
  """
  @spec stop_driver(Types.id()) :: :ok | {:error, :not_found}
  def stop_driver(driver_id) do
    case DriverRegistry.whereis(driver_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      {:error, :not_found} = error -> error
    end
  end
end
