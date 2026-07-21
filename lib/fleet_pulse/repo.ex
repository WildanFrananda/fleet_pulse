defmodule FleetPulse.Repo do
  use Ecto.Repo,
    otp_app: :fleet_pulse,
    adapter: Ecto.Adapters.Postgres
end
