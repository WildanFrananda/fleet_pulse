defmodule FleetPulse.GrpcDrain do
  @moduledoc """
  Stops the gRPC server taking new calls on SIGTERM, then waits for the ones already running.
  """

  use GenServer

  require Logger

  @counters {__MODULE__, :counters}
  @in_flight 1
  @draining 2
  @poll_ms 50
  @default_budget_ms 5_000
  @shutdown_slack_ms 1_000

  @typep state :: %{listener: String.t() | nil, budget_ms: pos_integer()}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: budget_ms() + @shutdown_slack_ms
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec entered() :: :ok
  def entered, do: add(@in_flight, 1)

  @spec left() :: :ok
  def left, do: add(@in_flight, -1)

  @spec in_flight() :: non_neg_integer()
  def in_flight, do: read(@in_flight)

  @spec draining?() :: boolean()
  def draining?, do: read(@draining) > 0

  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    Process.flag(:trap_exit, true)
    :persistent_term.put(@counters, :counters.new(2, [:write_concurrency]))

    {:ok, %{listener: listener(), budget_ms: budget_ms()}}
  end

  @impl GenServer
  @spec terminate(term(), state()) :: :ok
  def terminate(_reason, state) do
    add(@draining, 1)
    suspend(state.listener)

    (System.monotonic_time(:millisecond) + state.budget_ms)
    |> wait()
    |> report()
  end

  @spec wait(integer()) :: non_neg_integer()
  defp wait(deadline), do: drain(in_flight(), deadline)

  @spec drain(non_neg_integer(), integer()) :: non_neg_integer()
  defp drain(0, _deadline), do: 0

  defp drain(remaining, deadline) do
    case System.monotonic_time(:millisecond) < deadline do
      true ->
        Process.sleep(@poll_ms)
        drain(in_flight(), deadline)

      false ->
        remaining
    end
  end

  @spec report(non_neg_integer()) :: :ok
  defp report(0), do: Logger.info("gRPC drained; no calls left in flight")

  defp report(remaining) do
    Logger.warning(
      "gRPC drain budget expired with #{remaining} call(s) still in flight; " <>
        "they are cut off when the listener stops"
    )
  end

  @spec suspend(String.t() | nil) :: :ok
  defp suspend(nil), do: :ok

  defp suspend(ref) do
    case :ranch.suspend_listener(ref) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("could not suspend #{ref}: #{inspect(reason)}")
    end
  end

  @spec listener() :: String.t() | nil
  defp listener do
    ref = inspect(FleetPulse.GrpcEndpoint)

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

  @spec budget_ms() :: pos_integer()
  defp budget_ms do
    :fleet_pulse
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:budget_ms, @default_budget_ms)
  end

  @spec add(pos_integer(), integer()) :: :ok
  defp add(index, delta) do
    case :persistent_term.get(@counters, nil) do
      nil -> :ok
      counters -> :counters.add(counters, index, delta)
    end
  end

  @spec read(pos_integer()) :: non_neg_integer()
  defp read(index) do
    case :persistent_term.get(@counters, nil) do
      nil -> 0
      counters -> :counters.get(counters, index)
    end
  end
end
