defmodule FleetPulseWeb.MerchantSocket do
  @moduledoc """
  The websocket a merchant application connects to for real-time order and telemetry updates.

  What this replaces: `FleetPulseWeb.MerchantToken`, signed by this service with its own
  `secret_key_base` and valid for thirty days. Identity is the only minter on this platform, and
  a thirty-day credential this service could neither rotate nor revoke was the longest-lived one
  anywhere on it.
  """

  use Phoenix.Socket

  alias FleetPulse.Security.AccessClaims
  alias FleetPulse.Security.TokenVerifier

  channel "merchant:*", FleetPulseWeb.MerchantChannel

  @type error :: :invalid_token | :malformed_claims | :not_a_merchant | :missing_token

  @impl Phoenix.Socket
  @spec connect(map(), Phoenix.Socket.t(), map()) ::
          {:ok, Phoenix.Socket.t()} | {:error, error()}
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    with {:ok, %AccessClaims{} = claims} <- TokenVerifier.verify_access(token),
         :ok <- merchant?(claims) do
      {:ok, assign(socket, :merchant_principal_id, claims.principal_id)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def connect(_params, _socket, _connect_info), do: {:error, :missing_token}

  @impl Phoenix.Socket
  @spec id(Phoenix.Socket.t()) :: String.t()
  def id(socket), do: "merchant_socket:#{socket.assigns.merchant_principal_id}"

  @spec merchant?(AccessClaims.t()) :: :ok | {:error, :not_a_merchant}
  defp merchant?(%AccessClaims{role: "seller"}), do: :ok
  defp merchant?(%AccessClaims{role: "admin"}), do: :ok
  defp merchant?(_claims), do: {:error, :not_a_merchant}
end
