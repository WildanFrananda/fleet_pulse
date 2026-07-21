defmodule FleetPulse.Tracking.DriverRegistry do
  @moduledoc """
  Typed wrapper around `Registry` for the driver_id → pid mapping.

  A raw `Registry` returns possibly-empty lists and loosely typed `:via`
  tuples. This module hides both behind an `{:ok, _} | {:error, _}` API, so
  the rest of the domain never touches Registry's data shapes directly.
  """

  alias FleetPulse.Types

  @registry __MODULE__

  @typedoc "The `:via` name a GenServer uses to register itself."
  @type via_name :: {:via, Registry, {module(), Types.id()}}

  @doc """
  Child spec so this module can be listed directly in a supervision tree.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Supervisor.child_spec({Registry, keys: :unique, name: @registry}, id: __MODULE__)
  end

  @doc """
  Builds the `:via` name for a driver.
  """
  @spec via(Types.id()) :: via_name()
  def via(driver_id), do: {:via, Registry, {@registry, driver_id}}

  @doc """
  Looks up the process owning a driver's live state.
  """
  @spec whereis(Types.id()) :: {:ok, pid()} | {:error, :not_found}
  def whereis(driver_id) do
    case Registry.lookup(@registry, driver_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Number of drivers currently held in memory.
  """
  @spec count() :: non_neg_integer()
  def count, do: Registry.count(@registry)

  @doc """
  Every driver_id that currently has a live process.
  """
  @spec driver_ids() :: [Types.id()]
  def driver_ids do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end
end
