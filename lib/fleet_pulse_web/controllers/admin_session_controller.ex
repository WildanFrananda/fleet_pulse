defmodule FleetPulseWeb.AdminSessionController do
  use FleetPulseWeb, :controller

  alias FleetPulse.Accounts
  alias FleetPulseWeb.AdminAuth

  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"admin" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_admin(email, password) do
      {:ok, admin} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> AdminAuth.log_in_admin(admin)

      {:error, :invalid_credentials} ->
        render(conn, :new, error_message: "Invalid email or password")
    end
  end

  def create(conn, _params), do: render(conn, :new, error_message: "Invalid email or password")

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully")
    |> AdminAuth.log_out_admin()
  end
end
