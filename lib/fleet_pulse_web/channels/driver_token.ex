defmodule FleetPulseWeb.DriverToken do
  @moduledoc """
  Signs and verifies the bearer token a driver app presents when opening its
  socket.

  `Phoenix.Token` signs with the endpoint's `secret_key_base`, so a token is
  tamper-evident without any server-side session store — which matters once
  the same driver may reconnect to a different node.

  The verified payload is re-checked against `FleetPulse.Types.id()` before it
  is trusted. A signature proves only that WE minted the token, not that its
  contents still make sense.
  """

  alias FleetPulse.Types
  alias FleetPulseWeb.Endpoint
  alias Phoenix.Token

  @salt "driver socket"
  @max_age_seconds 60 * 60 * 24 * 7

  @typedoc "Why a presented token was refused."
  @type error :: :invalid_token | :expired_token

  @doc """
  Mints a token for a driver. Valid for seven days.
  """
  @spec sign(Types.id()) :: String.t()
  def sign(driver_id), do: Token.sign(Endpoint, @salt, driver_id)

  @doc """
  Verifies a presented token and returns the driver it identifies.
  """
  @spec verify(term()) :: {:ok, Types.id()} | {:error, error()}
  def verify(token) when is_binary(token) do
    case Token.verify(Endpoint, @salt, token, max_age: @max_age_seconds) do
      {:ok, driver_id} when is_integer(driver_id) and driver_id > 0 -> {:ok, driver_id}
      {:error, :expired} -> {:error, :expired_token}
      _invalid -> {:error, :invalid_token}
    end
  end

  def verify(_token), do: {:error, :invalid_token}
end
