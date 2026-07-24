defmodule FleetPulseWeb.DriverSessionController do
  @moduledoc """
  Issues a driver bearer token in exchange for phone + password.

  Stateless: unlike the admin login there is no cookie or session. The client
  (the driver app) stores the returned token and presents it when opening its
  socket. This is the only place a `DriverToken` is minted for a real driver.
  """

  use FleetPulseWeb, :controller

  alias FleetPulse.Tracking
  alias FleetPulseWeb.DriverToken

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"phone" => phone, "password" => password})
      when is_binary(phone) and is_binary(password) do
    case Tracking.authenticate_driver(phone, password) do
      {:ok, driver} ->
        conn
        |> put_status(:created)
        |> json(%{
          token: DriverToken.sign(driver.id),
          driver_id: driver.id,
          expires_in: DriverToken.max_age_seconds()
        })

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "phone and password are required"})
  end
end
