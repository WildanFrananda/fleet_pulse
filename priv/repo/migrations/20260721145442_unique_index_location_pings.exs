defmodule FleetPulse.Repo.Migrations.UniqueIndexLocationPings do
  use Ecto.Migration

  def up do
    drop index(:location_pings, [:driver_id, :recorded_at])
    create unique_index(:location_pings, [:driver_id, :recorded_at])
  end

  def down do
    drop index(:location_pings, [:driver_id, :recorded_at])
    create index(:location_pings, [:driver_id, :recorded_at])
  end
end
