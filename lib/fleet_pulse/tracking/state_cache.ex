defmodule FleetPulse.Tracking.StateCache do
  @moduledoc """
  ETS-backed cache of each driver's last known live state.

  The table is owned by THIS process, not by the driver processes, so it
  survives a `DriverState` crash. That is the entire point: a crashed driver
  process rehydrates from memory with zero queries. Only a full node restart
  leaves the table empty and forces a database read.

  The table is `:public` on purpose. At the PRD's target of ~2000 updates per
  second, routing every write through this GenServer would make it the system
  bottleneck. Driver processes write directly; this process only owns the
  table and keeps it alive.
  """

  use GenServer

  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Types

  @table __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a driver's current state. Called on every update.
  """
  @spec put(Types.id(), DriverState.t()) :: :ok
  def put(driver_id, state) do
    _ = :ets.insert(@table, {driver_id, state})
    :ok
  end

  @doc """
  Reads a driver's cached state, if the node has seen it since booting.
  """
  @spec fetch(Types.id()) :: {:ok, DriverState.t()} | {:error, :not_found}
  def fetch(driver_id) do
    case :ets.lookup(@table, driver_id) do
      [{^driver_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Every cached driver that currently has a known position.

  Exists so callers never have to name the ETS table themselves — the table
  name is a private implementation detail of this module. Order is
  unspecified; this is a `:set`.
  """
  @spec with_coordinates() :: [DriverState.t()]
  def with_coordinates do
    @table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {_driver_id, %DriverState{coordinates: nil}} -> []
      {_driver_id, %DriverState{} = state} -> [state]
    end)
  end

  @doc """
  Evicts a driver, e.g. after a permanent logout.
  """
  @spec delete(Types.id()) :: :ok
  def delete(driver_id) do
    _ = :ets.delete(@table, driver_id)
    :ok
  end

  @doc """
  Number of cached drivers. Returns 0 before the table exists.
  """
  @spec size() :: non_neg_integer()
  def size do
    case :ets.info(@table, :size) do
      :undefined -> 0
      size -> size
    end
  end

  @impl GenServer
  @spec init(keyword()) :: {:ok, :ready}
  def init(_opts) do
    _table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, :ready}
  end
end
