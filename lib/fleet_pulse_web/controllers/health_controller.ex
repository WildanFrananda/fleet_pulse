defmodule FleetPulseWeb.HealthController do
  @moduledoc """
  Probe endpoints for load balancers and orchestrators.

  `live` answers "is the BEAM up?" — trivially 200, no dependencies. Use it for
  a liveness probe: if it fails, restart the node.

  `ready` answers "can we actually serve?" — it pings the database. Use it for
  a readiness probe / load-balancer health check: a node with no database
  should be pulled from rotation, not restarted.

  Both answer JSON in the shape every other service in the estate uses, which
  `scripts/probe_conformance.sh` asserts. They used to send the bare strings
  "ok" and "ready": the right semantics in the wrong shape, so anything reading
  the platform's probes had to special-case this one service. Neither body names
  the framework, its version or the driver's error — the routes are
  unauthenticated by necessity, because the orchestrator holds no token.
  """

  use FleetPulseWeb, :controller

  alias Ecto.Adapters.SQL
  alias FleetPulse.Repo

  @spec live(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live(conn, _params) do
    json(conn, %{status: "ok", service: "kinetix-matching-service"})
  end

  @spec ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ready(conn, _params) do
    reply(database_ok?(), conn)
  end

  @spec reply(boolean(), Plug.Conn.t()) :: Plug.Conn.t()
  defp reply(true, conn) do
    json(conn, %{status: "ok", database: "reachable"})
  end

  defp reply(false, conn) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{status: "unavailable", database: "unreachable"})
  end

  @spec database_ok?() :: boolean()
  defp database_ok? do
    case SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> true
      {:error, _reason} -> false
    end
  rescue
    _error -> false
  end
end
