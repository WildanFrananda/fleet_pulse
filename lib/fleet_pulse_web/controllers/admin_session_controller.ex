defmodule FleetPulseWeb.AdminSessionController do
  @moduledoc """
  The dispatch console's login.

  The password is forwarded to identity and never compared here — this service holds no
  credential to compare it against. What comes back is verified with the same verifier every
  other route uses, so there is exactly one place that decides a token is good.
  """

  use FleetPulseWeb, :controller

  alias FleetPulse.Security.IdentityLogin
  alias FleetPulseWeb.AdminAuth

  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"admin" => %{"email" => email, "password" => password}}) do
    case IdentityLogin.log_in(email, password) do
      {:ok, operator} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> AdminAuth.log_in_operator(operator)

      {:error, reason} when reason in [:invalid_credentials, :not_an_operator] ->
        render(conn, :new, error_message: "Invalid email or password")

      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> render(:new,
          error_message: "Too many sign-in attempts. Wait a minute, then try again."
        )

      {:error, :two_factor_required} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:new,
          error_message:
            "This account uses two-factor authentication, which this console cannot complete yet."
        )

      {:error, :identity_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> render(:new, error_message: "Sign-in is temporarily unavailable. Try again shortly.")
    end
  end

  def create(conn, _params), do: render(conn, :new, error_message: "Invalid email or password")

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully")
    |> AdminAuth.log_out_operator()
  end
end
