defmodule FleetPulse.Accounts.AdminTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Accounts.Admin

  defp changeset(overrides \\ %{}) do
    attrs = Map.merge(%{email: "ADMIN@Fleet.com", password: "supersecret123"}, overrides)
    Admin.registration_changeset(%Admin{}, attrs)
  end

  test "accepts a valid registration" do
    assert changeset().valid?
  end

  test "downcases the email" do
    assert Ecto.Changeset.get_change(changeset(), :email) == "admin@fleet.com"
  end

  test "hashes the password and drops the plaintext" do
    changes = changeset().changes

    assert is_binary(changes.hashed_password)
    refute Map.has_key?(changes, :password)
    refute changes.hashed_password == "supersecret123"
  end

  test "requires an email that looks like an email" do
    refute changeset(%{email: "not-an-email"}).valid?
    refute changeset(%{email: "has space@x.com"}).valid?
  end

  test "rejects a password shorter than 12 or longer than 72 bytes" do
    refute changeset(%{password: "short"}).valid?
    refute changeset(%{password: String.duplicate("a", 73)}).valid?
    assert changeset(%{password: String.duplicate("a", 72)}).valid?
  end

  test "does not hash when the changeset is invalid" do
    refute Map.has_key?(changeset(%{password: "short"}).changes, :hashed_password)
  end

  describe "valid_password?/2" do
    test "is true for the right password, false for the wrong one" do
      admin = %Admin{hashed_password: Bcrypt.hash_pwd_salt("supersecret123")}

      assert Admin.valid_password?(admin, "supersecret123")
      refute Admin.valid_password?(admin, "wrong")
    end

    test "is false when there is no stored hash" do
      refute Admin.valid_password?(%Admin{hashed_password: nil}, "anything")
    end
  end
end
