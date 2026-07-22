defmodule FleetPulseWeb.DriverSocket do
  @moduledoc """
  The websocket a driver's mobile app connects to.

  Authentication happens once, here, at connect time — not per message. The
  verified driver id is stashed in socket assigns and is the ONLY identity the
  channel trusts afterwards.
  """

  use Phoenix.Socket

  alias FleetPulseWeb.DriverToken

  channel "driver:*", FleetPulseWeb.DriverChannel

  @impl Phoenix.Socket
  @spec connect(map(), Phoenix.Socket.t(), map()) ::
          {:ok, Phoenix.Socket.t()} | {:error, DriverToken.error() | :missing_token}
  def connect(%{"token" => token}, socket, _connect_info) do
    case DriverToken.verify(token) do
      {:ok, driver_id} -> {:ok, assign(socket, :driver_id, driver_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  def connect(_params, _socket, _connect_info), do: {:error, :missing_token}

  @doc """
  Identifies every socket belonging to one driver.

  Returning a stable id lets the server force-disconnect a driver from
  anywhere — `FleetPulseWeb.Endpoint.broadcast("driver_socket:7", "disconnect", %{})`
  — which is what you reach for when a token is revoked.
  """
  @impl Phoenix.Socket
  @spec id(Phoenix.Socket.t()) :: String.t()
  def id(socket), do: "driver_socket:#{socket.assigns.driver_id}"
end
