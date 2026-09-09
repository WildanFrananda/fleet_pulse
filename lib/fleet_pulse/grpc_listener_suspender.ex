defmodule FleetPulse.GrpcListenerSuspender do
  @moduledoc """
  Stops the gRPC server taking new calls, from the first moment of shutdown.
  """

  use GenServer

  require Logger

  alias FleetPulse.GrpcDrain

  @typep state :: %{listener: String.t() | nil}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok, %{listener: listener(Keyword.get(opts, :endpoint, FleetPulse.GrpcEndpoint))}}
  end

  @impl GenServer
  @spec terminate(term(), state()) :: :ok
  def terminate(_reason, state) do
    GrpcDrain.refuse_new_calls()
    suspend(state.listener)
  end

  @spec suspend(String.t() | nil) :: :ok
  defp suspend(nil), do: :ok

  defp suspend(ref) do
    case :ranch.suspend_listener(ref) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("could not suspend #{ref}: #{inspect(reason)}")
    end
  end

  @spec listener(module()) :: String.t() | nil
  defp listener(endpoint) do
    ref = inspect(endpoint)

    listener(ref, Map.has_key?(:ranch.info(), ref))
  end

  @spec listener(String.t(), boolean()) :: String.t() | nil
  defp listener(ref, true), do: ref

  defp listener(ref, false) do
    Logger.warning(
      "no ranch listener named #{ref}; the gRPC port will keep accepting connections while draining"
    )

    nil
  end
end
