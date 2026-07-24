defmodule FleetPulse.Tracking.DriverTest do
  use ExUnit.Case, async: true

  alias FleetPulse.DataCase
  alias FleetPulse.Tracking.Driver
  alias FleetPulse.TrackingFixtures

  defp changeset(overrides \\ %{}) do
    Driver.changeset(%Driver{}, TrackingFixtures.driver_attrs(overrides))
  end

  describe "changeset/2" do
    test "accepts valid attributes" do
      assert changeset().valid?
    end

    test "upcases the vehicle plate before it reaches the unique index" do
      changeset = changeset(%{vehicle_plate: "b 1234 xy"})
      assert Ecto.Changeset.get_change(changeset, :vehicle_plate) == "B 1234 XY"
    end

    test "requires name, phone and vehicle_plate" do
      changeset = Driver.changeset(%Driver{}, %{})
      errors = DataCase.errors_on(changeset)

      refute changeset.valid?
      assert errors.name == ["can't be blank"]
      assert errors.phone == ["can't be blank"]
      assert errors.vehicle_plate == ["can't be blank"]
    end

    test "rejects a name shorter than 2 or longer than 120 characters" do
      refute changeset(%{name: "A"}).valid?
      refute changeset(%{name: String.duplicate("A", 121)}).valid?
      assert changeset(%{name: String.duplicate("A", 120)}).valid?
    end

    test "rejects malformed phone numbers" do
      for bad <- ["12345", "08-1234-5678", "not a phone", String.duplicate("9", 16)] do
        refute changeset(%{phone: bad}).valid?, "expected #{inspect(bad)} to be rejected"
      end

      assert changeset(%{phone: "+6281234567890"}).valid?
    end

    test "keeps capacity_kg within the range the CHECK constraint allows" do
      refute changeset(%{capacity_kg: -1}).valid?
      refute changeset(%{capacity_kg: 5_001}).valid?
      assert changeset(%{capacity_kg: 0}).valid?
      assert changeset(%{capacity_kg: 5_000}).valid?
    end

    test "rejects a status outside the enum" do
      changeset = changeset(%{status: :flying})

      refute changeset.valid?
      assert DataCase.errors_on(changeset).status == ["is invalid"]
    end

    test "defaults status to :offline" do
      assert %Driver{}.status == :offline
    end
  end

  describe "status_changeset/2" do
    test "accepts every declared status" do
      for status <- Driver.statuses() do
        assert Driver.status_changeset(%Driver{}, %{status: status}).valid?
      end
    end

    test "rejects an unknown status" do
      refute Driver.status_changeset(%Driver{}, %{status: :napping}).valid?
    end

    test "rejects an explicit nil status" do
      changeset = Driver.status_changeset(%Driver{}, %{status: nil})

      refute changeset.valid?
      assert DataCase.errors_on(changeset).status == ["can't be blank"]
    end

    test "is a no-op when the payload carries no status at all" do
      changeset = Driver.status_changeset(%Driver{}, %{})

      assert changeset.valid?
      assert changeset.changes == %{}
    end
  end

  describe "statuses/0" do
    test "matches the values the DB CHECK constraint permits" do
      assert Driver.statuses() == [:online, :busy, :offline]
    end
  end

  describe "password_changeset/2" do
    test "hashes the password and drops the plaintext" do
      changes = Driver.password_changeset(%Driver{}, %{password: "supersecret123"}).changes

      assert is_binary(changes.hashed_password)
      refute Map.has_key?(changes, :password)
    end

    test "rejects a password shorter than 12 or longer than 72 bytes" do
      refute Driver.password_changeset(%Driver{}, %{password: "short"}).valid?
      refute Driver.password_changeset(%Driver{}, %{password: String.duplicate("a", 73)}).valid?
      assert Driver.password_changeset(%Driver{}, %{password: String.duplicate("a", 72)}).valid?
    end
  end

  describe "valid_password?/2" do
    test "true for the right password, false for the wrong one" do
      driver = %Driver{hashed_password: Bcrypt.hash_pwd_salt("supersecret123")}

      assert Driver.valid_password?(driver, "supersecret123")
      refute Driver.valid_password?(driver, "nope")
    end

    test "false when the driver has no password set" do
      refute Driver.valid_password?(%Driver{hashed_password: nil}, "anything")
    end
  end
end
