alias FleetPulse.Accounts
alias FleetPulse.Accounts.Admin
alias FleetPulse.Repo

admin_email = "admin@fleetpulse.local"

unless Repo.get_by(Admin, email: admin_email) do
  {:ok, _admin} = Accounts.create_admin(%{email: admin_email, password: "changeme123456"})
  IO.puts("Seeded admin #{admin_email} (password: changeme123456)")
end
