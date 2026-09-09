defmodule FleetPulse.Observability.GrpcMetricsInterceptor do
  @moduledoc """
  Counts every call this server answers, and holds the count of the ones still running.
  """

  @behaviour GRPC.Server.Interceptor

  alias FleetPulse.GrpcDrain
  alias FleetPulse.Observability.Metrics

  @unknown_method "unknown"

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
    dispatch(GrpcDrain.draining?(), req, stream, next)
  end

  @spec dispatch(
          boolean(),
          struct() | nil,
          GRPC.Server.Stream.t(),
          (struct() | nil, GRPC.Server.Stream.t() -> any())
        ) ::
          any()
  defp dispatch(true, _req, stream, _next) do
    record(stream, GRPC.Status.unavailable())

    raise GRPC.RPCError,
      status: GRPC.Status.unavailable(),
      message: "this instance is shutting down"
  end

  defp dispatch(false, req, stream, next) do
    GrpcDrain.entered()

    try do
      result = next.(req, stream)
      record(stream, GRPC.Status.ok())
      result
    rescue
      error in GRPC.RPCError ->
        record(stream, error.status)
        reraise error, __STACKTRACE__

      error ->
        record(stream, GRPC.Status.unknown())
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        record(stream, GRPC.Status.unknown())
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      GrpcDrain.left()
    end
  end

  @spec record(GRPC.Server.Stream.t(), non_neg_integer()) :: :ok
  defp record(stream, status) do
    :telemetry.execute(
      Metrics.grpc_server_call_event(),
      %{count: 1},
      %{grpc_method: method(stream), grpc_code: GRPC.Status.code_name(status)}
    )
  end

  @spec method(GRPC.Server.Stream.t()) :: String.t()
  defp method(%GRPC.Server.Stream{service_name: service, method_name: method})
       when is_binary(service) and is_binary(method),
       do: "#{service}/#{method}"

  defp method(_stream), do: @unknown_method
end
