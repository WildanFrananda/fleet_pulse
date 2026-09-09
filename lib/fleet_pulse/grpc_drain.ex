defmodule FleetPulse.GrpcDrain do
  @moduledoc """
  Holds the count of gRPC calls in flight, and waits for them at shutdown.
  """

  use GenServer

  require Logger

  @counters {__MODULE__, :counters}
  @in_flight 1
  @draining 2
  @poll_ms 50
  @default_budget_ms 5_000
  @shutdown_slack_ms 1_000

  @typep state :: %{budget_ms: pos_integer()}

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

  @spec in_flight() :: integer()
  def in_flight, do: read(@in_flight)

  @spec draining?() :: boolean()
  def draining?, do: read(@draining) > 0

  @spec refuse_new_calls() :: :ok
  def refuse_new_calls, do: add(@draining, 1)

  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    Process.flag(:trap_exit, true)
    :persistent_term.put(@counters, :counters.new(2, [:write_concurrency]))

    {:ok, %{budget_ms: budget_ms()}}
  end

  @impl GenServer
  @spec terminate(term(), state()) :: :ok
  def terminate(_reason, state) do
    refuse_new_calls()

    (System.monotonic_time(:millisecond) + state.budget_ms)
    |> wait()
    |> report()
  end

  @spec wait(integer()) :: integer()
  defp wait(deadline), do: drain(in_flight(), deadline)

  @spec drain(integer(), integer()) :: integer()
  defp drain(remaining, _deadline) when remaining <= 0, do: remaining

  defp drain(remaining, deadline) do
    case System.monotonic_time(:millisecond) < deadline do
      true ->
        Process.sleep(@poll_ms)
        drain(in_flight(), deadline)

      false ->
        remaining
    end
  end

  @spec report(integer()) :: :ok
  defp report(0), do: Logger.info("gRPC drained; no calls left in flight")

  defp report(remaining) when remaining < 0 do
    Logger.warning(
      "gRPC in-flight count is #{remaining}, which cannot be a number of calls; the counter was " <>
        "replaced while calls were running, so this drain cannot say what it waited for"
    )
  end

  defp report(remaining) do
    Logger.warning(
      "gRPC drain budget expired with #{remaining} call(s) still in flight; " <>
        "they are cut off when the listener stops"
    )
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

  @spec read(pos_integer()) :: integer()
  defp read(index) do
    case :persistent_term.get(@counters, nil) do
      nil -> 0
      counters -> :counters.get(counters, index)
    end
  end
end
