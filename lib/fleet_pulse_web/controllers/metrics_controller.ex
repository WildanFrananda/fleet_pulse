defmodule FleetPulseWeb.MetricsController do
  @moduledoc """
  Serves the Prometheus scrape on this service's own HTTP port, unauthenticated.
  """

  use FleetPulseWeb, :controller

  require Logger

  alias FleetPulse.Observability.Metrics

  @exposition "text/plain; version=0.0.4; charset=utf-8"
  @plain "text/plain; charset=utf-8"

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    reply(Metrics.scrape(), conn)
  end

  @spec reply({:ok, String.t()} | {:error, String.t()}, Plug.Conn.t()) :: Plug.Conn.t()
  defp reply({:ok, body}, conn) do
    conn
    |> put_resp_header("content-type", @exposition)
    |> send_resp(200, body)
  end

  defp reply({:error, reason}, conn) do
    Logger.error("metrics scrape failed: #{reason}")

    conn
    |> put_resp_header("content-type", @plain)
    |> send_resp(503, "metrics unavailable\n")
  end
end
