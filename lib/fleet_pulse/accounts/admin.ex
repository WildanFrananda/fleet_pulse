defmodule FleetPulse.Accounts.Admin do
  @moduledoc """
  Ecto schema for a dispatch operator — a Pure Data Object.

  The plaintext password lives only in the virtual `:password` field during a
  changeset; it is hashed into `:hashed_password` and dropped before insert, so
  it never reaches the database. Both fields are `redact: true`, keeping them
  out of logs and `inspect/1` output.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FleetPulse.Types

  @typedoc """
  A persisted admin. `password` is virtual and present only mid-changeset.
  """
  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Types.id() | nil,
          email: String.t() | nil,
          hashed_password: String.t() | nil,
          password: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @typedoc "A changeset whose data is guaranteed to be an `t()`."
  @type changeset :: Ecto.Changeset.t(t())

  @max_password_bytes 72

  schema "admins" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating an admin from an email and a plaintext password.
  """
  @spec registration_changeset(t(), map()) :: changeset()
  def registration_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/,
      message: "must have an @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email)
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
  Verifies a plaintext password against an admin's stored hash.

  Runs a dummy hash when there is nothing to compare, so a caller cannot tell
  a missing hash apart from a wrong password by timing the response.
  """
  @spec valid_password?(t(), String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and is_binary(password) do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_admin, _password) do
    Bcrypt.no_user_verify()
    false
  end
end
