defmodule FleetPulse.Repo.Migrations.CreateDrivers do
  use Ecto.Migration

  def change do
    create table(:drivers) do
      add :name, :string, size: 120, null: false
      add :phone, :string, size: 20, null: false
      add :vehicle_plate, :string, size: 20, null: false
      add :capacity_kg, :integer, null: false, default: 0
      add :status, :string, null: false, default: "offline"
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:drivers, [:phone])
    create unique_index(:drivers, [:vehicle_plate])

    create index(:drivers, [:active, :status])

    create constraint(:drivers, :drivers_status_valid,
             check: "status IN ('online', 'busy', 'offline')"
           )

    create constraint(:drivers, :drivers_capacity_kg_non_negative, check: "capacity_kg >= 0")
  end
end
