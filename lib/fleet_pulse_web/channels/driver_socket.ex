defmodule FleetPulseWeb.DriverSocket do
  @moduledoc """
  The websocket a driver's mobile app connects to.
  """

  use Phoenix.Socket

  alias FleetPulse.Security.AccessClaims
  alias FleetPulse.Security.TokenVerifier
  alias FleetPulse.Tracking

  channel "driver:*", FleetPulseWeb.DriverChannel

  @type error ::
          :invalid_token
          | :malformed_claims
          | :not_a_courier
          | :unlinked
          | :missing_token
          | :identity_unavailable

  @impl Phoenix.Socket
  @spec connect(map(), Phoenix.Socket.t(), map()) ::
          {:ok, Phoenix.Socket.t()} | {:error, error()}
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    with {:ok, %AccessClaims{} = claims} <- TokenVerifier.verify_access(token),
         :ok <- courier?(claims),
         {:ok, driver} <- Tracking.driver_for_principal(claims.principal_id) do
      {:ok, assign(socket, :driver_id, driver.id)}
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
  def id(socket), do: "driver_socket:#{socket.assigns.driver_id}"

  @spec courier?(AccessClaims.t()) :: :ok | {:error, :not_a_courier}
  defp courier?(%AccessClaims{role: "courier"}), do: :ok
  defp courier?(%AccessClaims{role: "admin"}), do: :ok
  defp courier?(_claims), do: {:error, :not_a_courier}
end
