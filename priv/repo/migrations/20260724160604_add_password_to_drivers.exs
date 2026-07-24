defmodule FleetPulse.Repo.Migrations.AddPasswordToDrivers do
  use Ecto.Migration

  def change do
    alter table(:drivers) do
      add :hashed_password, :string
    end
  end
end
