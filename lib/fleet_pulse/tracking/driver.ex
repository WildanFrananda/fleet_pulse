defmodule FleetPulse.Tracking.Driver do
  @moduledoc """
  Ecto schema for fleet drivers — a Pure Data Object (PODO).

  This module has NO behavior: no `save/0`, `update/0`, or queries.
  All persistence resides in `FleetPulse.Tracking` (context). Here
  there is only the data form + incoming attribute validation rules.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FleetPulse.Types

  @typedoc "Driver availability status. Mirror of `@statuses` — keep them in sync."
  @type status :: Types.driver_status()

  @typedoc """
  Persist driver record.

  All fields are `| nil` because `%Driver{}` is plain (before `cast/4` or load
  from the DB) contains `nil` everywhere. Write `id:Types.id()` without `| nil`
  is the most common typespec lie in Ecto projects — Direct Dialyzer
  reject it once you create a manual struct.
  """
  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Types.id() | nil,
          name: String.t() | nil,
          phone: String.t() | nil,
          vehicle_plate: String.t() | nil,
          capacity_kg: non_neg_integer() | nil,
          status: status() | nil,
          active: boolean() | nil,
          hashed_password: String.t() | nil,
          password: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @typedoc "A changeset whose data is guaranteed to be of type `t()`."
  @type changeset :: Ecto.Changeset.t(t())

  @statuses [:online, :busy, :offline]
  @required_fields [:name, :phone, :vehicle_plate]
  @optional_fields [:capacity_kg, :status, :active]

  schema "drivers" do
    field :name, :string
    field :phone, :string
    field :vehicle_plate, :string
    field :capacity_kg, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :offline
    field :active, :boolean, default: true
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime)
  end

  @max_password_bytes 72

  @doc """
  A list of valid states — a single source for validation, seeds, and UI choices.
  """
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  Changeset for full builds and updates.
  """
  @spec changeset(t(), map()) :: changeset()
  def changeset(%__MODULE__{} = driver, attrs) do
    driver
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 2, max: 120)
    |> validate_format(:phone, ~r/\A\+?[0-9]{8,15}\z/, message: "must be 8-15 digits")
    |> validate_number(:capacity_kg, greater_than_or_equal_to: 0, less_than_or_equal_to: 5_000)
    |> update_change(:vehicle_plate, &String.upcase/1)
    |> unique_constraint(:phone)
    |> unique_constraint(:vehicle_plate)
    |> check_constraint(:capacity_kg, name: :drivers_capacity_kg_non_negative)
  end

  @doc """
  Changeset for setting or changing a driver's login password.

  The plaintext lives only in the virtual `:password` field; it is hashed into
  `:hashed_password` and dropped before persistence.
  """
  @spec password_changeset(t(), map()) :: changeset()
  def password_changeset(%__MODULE__{} = driver, attrs) do
    driver
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: @max_password_bytes, count: :bytes)
    |> put_password_hash()
  end

  @spec put_password_hash(changeset()) :: changeset()
  defp put_password_hash(
         %Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset
       ) do
    changeset
    |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp put_password_hash(changeset), do: changeset

  @doc """
  Verifies a plaintext password against a driver's stored hash.

  Runs a dummy hash when there is no stored password, so a driver who was never
  given credentials is indistinguishable by timing from a wrong password.
  """
  @spec valid_password?(t(), String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and is_binary(password) do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_driver, _password) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Narrow changeset for state transitions only.

  Used by `Tracking.DriverState` (Stage 2) when flushing state from memory.
  Intentionally accepts `map()` instead of `status()`, so that invalid values ​​result in an
  invalid changeset — not a `FunctionClauseError`. See CLAUDE.md §4: do not
  raise for normal control flow.
  """
  @spec status_changeset(t(), map()) :: changeset()
  def status_changeset(%__MODULE__{} = driver, attrs) do
    driver
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end
end
