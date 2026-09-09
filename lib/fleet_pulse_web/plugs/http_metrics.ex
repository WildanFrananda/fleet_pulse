defmodule FleetPulseWeb.Plugs.HttpMetrics do
  @moduledoc """
  Times and counts every request this endpoint answers, under the estate's names.
  """

  @behaviour Plug

  alias FleetPulse.Observability.Metrics
  alias Plug.Conn

  @methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS TRACE CONNECT)
  @other_method "OTHER"
  @unmatched "unmatched"
  @unknown_status "unknown"

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Conn.t(), keyword()) :: Conn.t()
  def call(conn, _opts) do
    start = System.monotonic_time()

    Conn.register_before_send(conn, &record(&1, start))
  end

  @spec record(Conn.t(), integer()) :: Conn.t()
  defp record(conn, start) do
    :telemetry.execute(
      Metrics.http_stop_event(),
      %{duration: System.monotonic_time() - start},
      %{method: method(conn.method), route: route(conn), status: status(conn.status)}
    )

    conn
  end

  @spec route(Conn.t()) :: String.t()
  defp route(conn) do
    FleetPulseWeb.Router
    |> Phoenix.Router.route_info(conn.method, conn.path_info, conn.host)
    |> template()
  end

  @spec template(map() | :error) :: String.t()
  defp template(%{route: route}) when is_binary(route), do: braced(route)
  defp template(_no_route), do: @unmatched

  @spec braced(String.t()) :: String.t()
  defp braced(route), do: route |> String.split("/") |> Enum.map_join("/", &segment/1)

  @spec segment(String.t()) :: String.t()
  defp segment(":" <> name), do: "{#{name}}"
  defp segment("*" <> name), do: "{#{name}}"
  defp segment(literal), do: literal

  @spec status(non_neg_integer() | nil) :: String.t()
  defp status(status) when is_integer(status), do: Integer.to_string(status)
  defp status(_unset), do: @unknown_status

  @spec method(String.t()) :: String.t()
  defp method(method) when method in @methods, do: method
  defp method(_other), do: @other_method
end
