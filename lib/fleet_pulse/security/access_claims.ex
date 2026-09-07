defmodule FleetPulse.Security.AccessClaims do
  @moduledoc """
  The claims an identity access token carries, after verification.

  A struct rather than the decoder's raw map, so nothing downstream reads a claim that was never
  asserted.

  `uid` is deliberately absent. It is identity's account id, and while this struct carried it the
  merchant socket and the orders table both used it — so a merchant reaching this service over
  gRPC (which has always carried `merchant_principal_id`) and the same merchant reaching it over
  HTTP were stored under two different names, and neither could be matched to the other.
  """

  @enforce_keys [:principal_id, :email, :role]
  defstruct [:principal_id, :email, :role]

  @type t :: %__MODULE__{
          principal_id: String.t(),
          email: String.t(),
          role: String.t()
        }

  @doc """
  Narrows a verified payload claim by claim.

  A token missing any of these is not a token this service can act on: defaulting one would
  attribute a driver's location, or a merchant's order, to whoever the default named.
  """
  @spec from_payload(map()) :: {:ok, t()} | {:error, :malformed_claims}
  def from_payload(payload) when is_map(payload) do
    with {:ok, principal_id} <- text(payload, "sub"),
         {:ok, email} <- text(payload, "email"),
         {:ok, role} <- text(payload, "role") do
      {:ok, %__MODULE__{principal_id: principal_id, email: email, role: role}}
    end
  end

  def from_payload(_payload), do: {:error, :malformed_claims}

  @spec text(map(), String.t()) :: {:ok, String.t()} | {:error, :malformed_claims}
  defp text(payload, name) do
    case Map.get(payload, name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :malformed_claims}
    end
  end
end
