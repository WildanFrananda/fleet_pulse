defmodule FleetPulseWeb.MerchantSocket do
  @moduledoc """
  The websocket a merchant application connects to for real-time order and telemetry updates.
  """

  use Phoenix.Socket

  alias FleetPulse.Security.AccessClaims
  alias FleetPulse.Security.TokenVerifier

  channel "merchant:*", FleetPulseWeb.MerchantChannel

  @type error ::
          :invalid_token
          | :malformed_claims
          | :not_a_merchant
          | :missing_token
          | :identity_unavailable

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

  @spec handle_error(Plug.Conn.t(), error()) :: Plug.Conn.t()
  def handle_error(conn, :identity_unavailable), do: Plug.Conn.send_resp(conn, 503, "")
  def handle_error(conn, _reason), do: Plug.Conn.send_resp(conn, 403, "")

  @impl Phoenix.Socket
  @spec id(Phoenix.Socket.t()) :: String.t()
  def id(socket), do: "merchant_socket:#{socket.assigns.merchant_principal_id}"

  @spec merchant?(AccessClaims.t()) :: :ok | {:error, :not_a_merchant}
  defp merchant?(%AccessClaims{role: "seller"}), do: :ok
  defp merchant?(%AccessClaims{role: "admin"}), do: :ok
  defp merchant?(_claims), do: {:error, :not_a_merchant}
end
