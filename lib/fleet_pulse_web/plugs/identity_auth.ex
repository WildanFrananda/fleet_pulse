defmodule FleetPulseWeb.Plugs.IdentityAuth do
  @moduledoc """
  Authenticates a JSON API request against identity's RS256 access tokens.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias FleetPulse.Security.TokenVerifier

  @behaviour Plug

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn
    |> get_req_header("authorization")
    |> authenticate(conn)
  end

  @spec authenticate([String.t()], Plug.Conn.t()) :: Plug.Conn.t()
  defp authenticate([header], conn) do
    case String.split(header, " ") do
      [scheme, token] -> grant(String.downcase(scheme), token, conn)
      _malformed -> unauthorized(conn)
    end
  end

  defp authenticate(_headers, conn), do: unauthorized(conn)

  @spec grant(String.t(), String.t(), Plug.Conn.t()) :: Plug.Conn.t()
  defp grant("bearer", token, conn) do
    case TokenVerifier.verify_access(token) do
      {:ok, claims} -> assign(conn, :current_caller, claims)
      {:error, :identity_unavailable} -> unavailable(conn)
      {:error, _reason} -> unauthorized(conn)
    end
  end

  defp grant(_scheme, _token, conn), do: unauthorized(conn)

  @spec unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
    |> halt()
  end

  @spec unavailable(Plug.Conn.t()) :: Plug.Conn.t()
  defp unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "identity_unavailable"})
    |> halt()
  end
end
