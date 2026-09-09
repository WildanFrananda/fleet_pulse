defmodule FleetPulseWeb.HttpMetrics do
  @moduledoc """
  Times and counts every request this endpoint answers, under the estate's names.
  """

  alias FleetPulse.Observability.Metrics
  alias Plug.Conn

  @methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS TRACE CONNECT)
  @transports ~w(websocket longpoll)
  @other_method "OTHER"
  @unmatched "unmatched"
  @unknown_status "unknown"

  @spec __before_compile__(Macro.Env.t()) :: Macro.t()
  defmacro __before_compile__(_env) do
    quote do
      defoverridable call: 2

      def call(conn, opts) do
        conn
        |> FleetPulseWeb.HttpMetrics.watch(__MODULE__)
        |> super(opts)
      end
    end
  end

  @spec watch(Conn.t(), module()) :: Conn.t()
  def watch(conn, endpoint) do
    start = System.monotonic_time()

    Conn.register_before_send(conn, &record(&1, start, endpoint))
  end

  @spec record(Conn.t(), integer(), module()) :: Conn.t()
  defp record(conn, start, endpoint) do
    :telemetry.execute(
      Metrics.http_stop_event(),
      %{duration: System.monotonic_time() - start},
      %{
        method: method(conn.method),
        route: route(conn, endpoint),
        status: status(conn.status)
      }
    )

    conn
  end

  @spec route(Conn.t(), module()) :: String.t()
  defp route(conn, endpoint) do
    FleetPulseWeb.Router
    |> Phoenix.Router.route_info(conn.method, conn.path_info, conn.host)
    |> template(conn.path_info, endpoint)
  end

  @spec template(map() | :error, [String.t()], module()) :: String.t()
  defp template(%{route: route}, _path_info, _endpoint) when is_binary(route), do: braced(route)
  defp template(_no_route, path_info, endpoint), do: socket_route(path_info, endpoint)

  @spec socket_route([String.t()], module()) :: String.t()
  defp socket_route(path_info, endpoint) do
    transport = List.last(path_info)
    prefix = "/" <> Enum.join(Enum.drop(path_info, -1), "/")

    transport
    |> socket_transport?(prefix, endpoint)
    |> socket_template(prefix, transport)
  end

  @spec socket_transport?(String.t() | nil, String.t(), module()) :: boolean()
  defp socket_transport?(transport, prefix, endpoint) do
    transport in @transports and declared_socket?(prefix, endpoint)
  end

  @spec socket_template(boolean(), String.t(), String.t() | nil) :: String.t()
  defp socket_template(true, prefix, transport), do: "#{prefix}/#{transport}"
  defp socket_template(false, _prefix, _transport), do: @unmatched

  @spec declared_socket?(String.t(), module()) :: boolean()
  defp declared_socket?(prefix, endpoint) do
    Enum.any?(endpoint.__sockets__(), &match?({^prefix, _socket, _opts}, &1))
  end

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
