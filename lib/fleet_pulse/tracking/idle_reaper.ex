defmodule FleetPulse.Tracking.IdleReaper do
  @moduledoc """
  Stops driver processes that have gone quiet.

  `DriverChannel` deliberately leaves a `DriverState` running when its channel
  dies, so a reconnect keeps its warm position instead of re-reading Postgres.
  Nothing else ever stops those processes. Without this reaper a driver who
  never comes back keeps its process AND its cache entry for the life of the
  node — and `PersistenceBatcher` re-persists that frozen position every
  interval, forever.

  Only `:offline` drivers are eligible. An `:online` or `:busy` driver has a
  live channel however quiet it happens to be, and killing it would break a
  working session.

  ## Two-stage decision

  The ETS scan is a cheap way to find CANDIDATES, but it can be stale by the
  time we act. The binding decision is re-made inside each candidate process
  by `DriverState.stop_if_idle/2`, which reads its own current state. That is
  the only place where "is this driver idle" can be answered without a race.
  """

  use GenServer

  require Logger

  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Tracking.StateCache

  @default_interval_ms 60_000
  @default_idle_after_ms 900_000

  @typedoc "Reaper process state."
  @type t :: %__MODULE__{interval_ms: pos_integer(), idle_after_ms: pos_integer()}

  @enforce_keys [:interval_ms, :idle_after_ms]
  defstruct [:interval_ms, :idle_after_ms]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Runs a sweep immediately instead of waiting for the next tick.
  """
  @spec reap_now() :: {:ok, non_neg_integer()}
  def reap_now, do: GenServer.call(__MODULE__, :reap_now, :infinity)

  @impl GenServer
  @spec init(keyword()) :: {:ok, t()}
  def init(_opts) do
    config = Application.get_env(:fleet_pulse, __MODULE__, [])

    state = %__MODULE__{
      interval_ms: interval_ms(Keyword.get(config, :interval_ms)),
      idle_after_ms: idle_after_ms(Keyword.get(config, :idle_after_ms))
    }

    _timer = schedule(state)
    {:ok, state}
  end

  @impl GenServer
  @spec handle_call(:reap_now, GenServer.from(), t()) :: {:reply, {:ok, non_neg_integer()}, t()}
  def handle_call(:reap_now, _from, state) do
    {:reply, {:ok, reap(state)}, state}
  end

  @impl GenServer
  @spec handle_info(term(), t()) :: {:noreply, t()}
  def handle_info(:reap, state) do
    _reaped = reap(state)
    _timer = schedule(state)
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.debug("#{inspect(__MODULE__)} ignore message: #{inspect(message)}")
    {:noreply, state}
  end

  @spec reap(t()) :: non_neg_integer()
  defp reap(%__MODULE__{idle_after_ms: idle_after_ms}) do
    cutoff = DateTime.add(DateTime.utc_now(), -idle_after_ms, :millisecond)

    reaped =
      StateCache.all()
      |> Enum.filter(&DriverState.idle?(&1, cutoff))
      |> Enum.count(&(DriverState.stop_if_idle(&1.driver_id, cutoff) == :stopped))

    log_reaped(reaped)
    reaped
  end

  @spec log_reaped(non_neg_integer()) :: :ok
  defp log_reaped(0), do: :ok

  defp log_reaped(reaped) do
    Logger.info("#{inspect(__MODULE__)} stopped #{reaped} idles driver(s)")
  end

  @spec schedule(t()) :: reference()
  defp schedule(%__MODULE__{interval_ms: interval_ms}) do
    Process.send_after(self(), :reap, interval_ms)
  end

  @spec interval_ms(term()) :: pos_integer()
  defp interval_ms(value) when is_integer(value) and value > 0, do: value
  defp interval_ms(_value), do: @default_interval_ms

  @spec idle_after_ms(term()) :: pos_integer()
  defp idle_after_ms(value) when is_integer(value) and value > 0, do: value
  defp idle_after_ms(_value), do: @default_idle_after_ms
end
