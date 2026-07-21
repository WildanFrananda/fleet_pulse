defmodule FleetPulse.Repo.Migrations.CreateLocationPings do
  use Ecto.Migration

  def change do
    create table(:location_pings) do
      add :driver_id, references(:drivers, on_delete: :restrict), null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :speed_kmh, :float
      add :bearing_deg, :float
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:location_pings, [:driver_id, :recorded_at])

    create constraint(:location_pings, :location_pings_latitude_range,
             check: "latitude >= -90 AND latitude <= 90"
           )

    create constraint(:location_pings, :location_pings_longitude_range,
             check: "longitude >= -180 AND longitude <= 180"
           )

    create constraint(:location_pings, :location_pings_speed_non_negative,
             check: "speed_kmh IS NULL OR speed_kmh >= 0"
           )

    create constraint(:location_pings, :location_pings_bearing_range,
             check: "bearing_deg IS NULL OR (bearing_deg >= 0 AND bearing_deg < 360)"
           )
  end
end
