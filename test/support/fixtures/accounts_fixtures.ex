defmodule FleetPulse.AccountsFixtures do
  @moduledoc """
  Test builders for the accounts context.
  """

  alias FleetPulse.Accounts
  alias FleetPulse.Accounts.Admin

  @typedoc "Attributes accepted by `FleetPulse.Accounts.create_admin/1`."
  @type attrs :: %{
          required(:email) => term(),
          required(:password) => term(),
          optional(atom()) => term()
        }

  @spec admin_attrs(map()) :: attrs()
  def admin_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        email: "admin#{System.unique_integer([:positive])}@fleet.com",
        password: "supersecret123"
      },
      overrides
    )
  end

  @spec admin_fixture(map()) :: Admin.t()
  def admin_fixture(overrides \\ %{}) do
    {:ok, admin} = Accounts.create_admin(admin_attrs(overrides))
    admin
  end
end
