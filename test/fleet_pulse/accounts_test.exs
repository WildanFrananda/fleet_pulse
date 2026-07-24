defmodule FleetPulse.AccountsTest do
  use FleetPulse.DataCase, async: true

  alias FleetPulse.Accounts

  defp admin_fixture(overrides) do
    attrs =
      Map.merge(
        %{email: "op#{System.unique_integer([:positive])}@fleet.com", password: "supersecret123"},
        overrides
      )

    {:ok, admin} = Accounts.create_admin(attrs)
    admin
  end

  describe "create_admin/1" do
    test "persists an admin with a hashed password" do
      assert {:ok, admin} =
               Accounts.create_admin(%{email: "a@fleet.com", password: "supersecret123"})

      assert admin.email == "a@fleet.com"
      assert is_binary(admin.hashed_password)
    end

    test "rejects a duplicate email" do
      _first = admin_fixture(%{email: "dup@fleet.com"})

      assert {:error, changeset} =
               Accounts.create_admin(%{email: "dup@fleet.com", password: "supersecret123"})

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "authenticate_admin/2" do
    test "returns the admin for correct credentials, case-insensitively" do
      admin = admin_fixture(%{email: "op@fleet.com"})

      assert {:ok, found} = Accounts.authenticate_admin("OP@fleet.com", "supersecret123")
      assert found.id == admin.id
    end

    test "rejects a wrong password" do
      admin_fixture(%{email: "op2@fleet.com"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_admin("op2@fleet.com", "wrong")
    end

    test "rejects an unknown email" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_admin("ghost@fleet.com", "supersecret123")
    end
  end
end
