defmodule FleetPulse.Accounts do
  @moduledoc """
  The accounts context — dispatch operator identities.

  Admins are seeded, not self-registered: there is no public sign-up. This
  module exposes just enough to create an admin (for seeds) and to
  authenticate one (for login).
  """

  alias FleetPulse.Accounts.Admin
  alias FleetPulse.Repo
  alias FleetPulse.Types

  @spec create_admin(map()) :: {:ok, Admin.t()} | {:error, Admin.changeset()}
  def create_admin(attrs) do
    %Admin{}
    |> Admin.registration_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_admin(Types.id()) :: {:ok, Admin.t()} | {:error, :not_found}
  def get_admin(id) do
    case Repo.get(Admin, id) do
      nil -> {:error, :not_found}
      %Admin{} = admin -> {:ok, admin}
    end
  end

  @doc """
  Authenticates an admin by email and password.

  Always spends the cost of one bcrypt verification, whether or not the email
  exists, so an attacker cannot enumerate valid emails by response time.
  """
  @spec authenticate_admin(String.t(), String.t()) ::
          {:ok, Admin.t()} | {:error, :invalid_credentials}
  def authenticate_admin(email, password) when is_binary(email) and is_binary(password) do
    Admin
    |> Repo.get_by(email: String.downcase(email))
    |> verify(password)
  end

  @spec verify(Admin.t() | nil, String.t()) :: {:ok, Admin.t()} | {:error, :invalid_credentials}
  defp verify(%Admin{} = admin, password) do
    authorised(Admin.valid_password?(admin, password), admin)
  end

  defp verify(nil, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  @spec authorised(boolean(), Admin.t()) :: {:ok, Admin.t()} | {:error, :invalid_credentials}
  defp authorised(true, admin), do: {:ok, admin}
  defp authorised(false, _admin), do: {:error, :invalid_credentials}
end
