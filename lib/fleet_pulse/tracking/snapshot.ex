defmodule FleetPulse.Tracking.Snapshot do
  @moduledoc """
  Rebuilds a driver's last known state from PostgreSQL.

  This is the cold path, reached only when `StateCache` has no entry — that
  is, after a full node restart.

  It is deliberately a module of its own rather than part of the
  `FleetPulse.Tracking` context: `DriverState` needs to read persisted state,
  but the context will drive driver processes. Keeping the read path separate
  avoids a dependency loop between them.
  """

  import Ecto.Query

  alias FleetPulse.Repo
  alias FleetPulse.Tracking.Driver
  alias FleetPulse.Tracking.LocationPing
  alias FleetPulse.Types

  @typedoc """
  The persisted fields worth restoring into a live driver process.

  A plain map rather than a `DriverState` struct: only `DriverState` should
  know how to build itself.
  """
  @type t :: %{
          status: Driver.status(),
          capacity_kg: non_neg_integer(),
          coordinates: Types.coordinates() | nil,
          speed_kmh: float() | nil,
          bearing_deg: float() | nil,
          recorded_at: DateTime.t() | nil
        }

  @doc """
  Loads a driver's persisted state.

  Returns `{:error, :not_found}` when no such driver exists, which lets the
  caller refuse to keep a process alive for a phantom driver.
  """
  @spec fetch(Types.id()) :: {:ok, t()} | {:error, :not_found}
  def fetch(driver_id) do
    case Repo.get(Driver, driver_id) do
      nil -> {:error, :not_found}
      %Driver{} = driver -> {:ok, build(driver, last_ping(driver_id))}
    end
  end

  @spec last_ping(Types.id()) :: LocationPing.t() | nil
  defp last_ping(driver_id) do
    LocationPing
    |> where([p], p.driver_id == ^driver_id)
    |> order_by([p], desc: p.recorded_at)
    |> limit(1)
    |> Repo.one()
  end

  @spec build(Driver.t(), LocationPing.t() | nil) :: t()
  defp build(%Driver{} = driver, nil) do
    %{
      status: driver.status,
      capacity_kg: driver.capacity_kg,
      coordinates: nil,
      speed_kmh: nil,
      bearing_deg: nil,
      recorded_at: nil
    }
  end

  defp build(%Driver{} = driver, %LocationPing{} = ping) do
    %{
      status: driver.status,
      capacity_kg: driver.capacity_kg,
      coordinates: {ping.latitude, ping.longitude},
      speed_kmh: ping.speed_kmh,
      bearing_deg: ping.bearing_deg,
      recorded_at: ping.recorded_at
    }
  end
end
