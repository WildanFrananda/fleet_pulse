defmodule FleetPulse.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :pickup_latitude, :float, null: false
      add :pickup_longitude, :float, null: false
      add :dropoff_latitude, :float, null: false
      add :dropoff_longitude, :float, null: false
      add :weight_kg, :integer, null: false, default: 0
      add :status, :string, null: false, default: "pending"
      add :driver_id, references(:drivers, on_delete: :restrict), null: true
      add :assigned_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:orders, [:status])
    create index(:orders, [:driver_id])

    create constraint(:orders, :orders_status_valid,
             check: "status IN ('pending', 'assigned', 'picked_up', 'delivered', 'cancelled')"
           )

    create constraint(:orders, :orders_weight_kg_non_negative, check: "weight_kg >= 0")

    create constraint(:orders, :orders_pickup_latitude_range,
             check: "pickup_latitude >= -90 AND pickup_latitude <= 90"
           )

    create constraint(:orders, :orders_pickup_longitude_range,
             check: "pickup_longitude >= -180 AND pickup_longitude <= 180"
           )

    create constraint(:orders, :orders_dropoff_latitude_range,
             check: "dropoff_latitude >= -90 AND dropoff_latitude <= 90"
           )

    create constraint(:orders, :orders_dropoff_longitude_range,
             check: "dropoff_longitude >= -180 AND dropoff_longitude <= 180"
           )

    create constraint(:orders, :orders_driver_presence,
             check: "driver_id IS NOT NULL OR status IN ('pending', 'cancelled')"
           )
  end
end
