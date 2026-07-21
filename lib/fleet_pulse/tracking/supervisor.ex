defmodule FleetPulse.Tracking.Supervisor do
  @moduledoc """
  Supervises the in-memory tracking subsystem.

  This subtree exists to contain faults. The root supervisor's default budget
  is 3 restarts in 5 seconds, shared with `FleetPulse.Repo` and the endpoint —
  so a background writer that crash-loops could exhaust it and terminate the
  whole application, destroying the very ETS table the crash-recovery path
  depends on. A dedicated subtree with its own budget keeps that blast radius
  local.
  """

  use Supervisor

  alias FleetPulse.Tracking.DriverRegistry
  alias FleetPulse.Tracking.DriverSupervisor
  alias FleetPulse.Tracking.PersistenceBatcher
  alias FleetPulse.Tracking.StateCache

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  @spec init(keyword()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(_opts) do
    children = [DriverRegistry, StateCache, DriverSupervisor] ++ batcher_children()

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end

  @spec batcher_children() :: [PersistenceBatcher]
  defp batcher_children do
    config = Application.get_env(:fleet_pulse, PersistenceBatcher, [])

    enabled_children(Keyword.get(config, :enabled, true))
  end

  @spec enabled_children(boolean()) :: [PersistenceBatcher]
  defp enabled_children(true), do: [PersistenceBatcher]
  defp enabled_children(false), do: []
end
