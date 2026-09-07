defmodule FleetPulse.Observability.RequestIdInterceptor do
  @moduledoc """
  Adopts the caller's correlation id as this call's `Logger` metadata.

  Kong mints `X-Request-Id` at the edge and order forwards it on every hop of the checkout saga.
  gRPC lower-cases metadata keys, so it arrives here as `x-request-id` — the same header, and worth
  knowing before grepping for the wrong one.

  Each call runs in its own process, so `Logger.metadata/1` here reaches every line the handler
  writes, not just the one below. `:request_id` is already in the console format (see
  `config/config.exs`) because `Plug.RequestId` sets the same key on the HTTP side — one id shape
  across both surfaces of this service.

  Declared *before* the peer authorization interceptor on the endpoint, so a refused call is logged
  under its caller's id too. A call that arrives without one keeps the id `GRPC.Server.Stream`
  already generated: correlating within this service is still better than nothing.
  """

  @behaviour GRPC.Server.Interceptor

  require Logger

  @header "x-request-id"

  @impl GRPC.Server.Interceptor
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl GRPC.Server.Interceptor
  @spec call(
          struct() | nil,
          GRPC.Server.Stream.t(),
          (struct() | nil, GRPC.Server.Stream.t() -> any()),
          keyword()
        ) ::
          any()
  def call(req, stream, next, _opts) do
    case request_id(stream) do
      nil -> :ok
      id -> Logger.metadata(request_id: id)
    end

    Logger.info("gRPC #{method(stream)}")

    next.(req, stream)
  end

  @spec request_id(GRPC.Server.Stream.t()) :: String.t() | nil
  defp request_id(%GRPC.Server.Stream{http_request_headers: headers}) when is_map(headers) do
    case Map.get(headers, @header) do
      value when is_binary(value) and value != "" -> value
      _absent -> nil
    end
  end

  defp request_id(_stream), do: nil

  @spec method(GRPC.Server.Stream.t()) :: String.t()
  defp method(%GRPC.Server.Stream{service_name: service, method_name: method}),
    do: "#{service}/#{method}"

  defp method(_stream), do: "an unknown method"
end
