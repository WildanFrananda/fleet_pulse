defmodule FleetPulse.Tracking.PersistenceBatcher do
  @moduledoc """
  Periodically writes each cached driver's latest position to `location_pings`
  (PRD 5.2).

  ## What this guarantees

  The last known position of every cached driver becomes durable within
  `interval_ms`.

  ## What it does NOT guarantee

    * Every ping. `StateCache` is an ETS `:set` keyed by driver_id, so
      positions arriving between two flushes overwrite one another and are
      never persisted. At a 3s ping cadence and a 30s interval, roughly one
      fix in ten survives. This table is a periodic SAMPLE of the position
      stream, not the stream itself.

    * Survival of a node restart. ETS is a cache, not a write-ahead log.
      Anything not yet flushed is gone.

  ## Why it cannot crash-loop

  `Repo.insert_all/3` raises on any constraint violation, and
  `on_conflict: :nothing` absorbs only unique violations — never CHECK or
  foreign-key ones. Because nothing evicts a rejected entry from the cache, a
  raising flush would re-read the same rows on every retry, forever, blocking
  persistence for every other driver too. So the database call is confined to
  `insert_all/1`, which converts the exception into a value at the I/O
  boundary. This process always reschedules and never dies from a database
  fault.
  """

  use GenServer

  require Logger

  alias FleetPulse.Repo
  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Tracking.LocationPing
  alias FleetPulse.Tracking.StateCache
  alias FleetPulse.Types

  @default_interval_ms 30_000
  @default_chunk_size 1_000
  @max_backoff 8

  @typedoc "Batcher process state."
  @type t :: %__MODULE__{
          interval_ms: pos_integer(),
          chunk_size: pos_integer(),
          consecutive_failures: non_neg_integer()
        }

  @typedoc """
  One row ready for `Repo.insert_all/3`.

  `insert_all` does not autogenerate timestamps, so `inserted_at` is supplied
  explicitly — once per flush, not once per row.
  """
  @type row :: %{
          driver_id: Types.id(),
          latitude: Types.latitude(),
          longitude: Types.longitude(),
          speed_kmh: float() | nil,
          bearing_deg: float() | nil,
          recorded_at: DateTime.t(),
          inserted_at: DateTime.t()
        }

  @typedoc "Outcome of a flush: rows written, or the fault that stopped it."
  @type outcome :: {:ok, non_neg_integer()} | {:error, term()}

  @enforce_keys [:interval_ms, :chunk_size]
  defstruct [:interval_ms, :chunk_size, consecutive_failures: 0]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Flushes immediately instead of waiting for the next tick. Useful in tests
  and for a graceful drain before shutdown.
  """
  @spec flush_now() :: outcome()
  def flush_now, do: GenServer.call(__MODULE__, :flush_now, :infinity)

  @impl GenServer
  @spec init(keyword()) :: {:ok, t()}
  def init(_opts) do
    config = Application.get_env(:fleet_pulse, __MODULE__, [])

    state = %__MODULE__{
      interval_ms: interval_ms(Keyword.get(config, :interval_ms)),
      chunk_size: chunk_size(Keyword.get(config, :chunk_size))
    }

    _timer = schedule(state)
    {:ok, state}
  end

  @impl GenServer
  @spec handle_call(:flush_now, GenServer.from(), t()) :: {:reply, outcome(), t()}
  def handle_call(:flush_now, _from, state) do
    outcome = flush(state)
    {:reply, outcome, record(state, outcome)}
  end

  @impl GenServer
  @spec handle_info(term(), t()) :: {:noreply, t()}
  def handle_info(:flush, state) do
    next = record(state, flush(state))
    _timer = schedule(next)
    {:noreply, next}
  end

  def handle_info(message, state) do
    Logger.debug("#{inspect(__MODULE__)} ignored message: #{inspect(message)}")
    {:noreply, state}
  end

  @spec flush(t()) :: outcome()
  defp flush(%__MODULE__{chunk_size: chunk_size}) do
    now = DateTime.utc_now()

    StateCache.with_coordinates()
    |> Enum.flat_map(&to_row(&1, now))
    |> Enum.chunk_every(chunk_size)
    |> Enum.reduce_while({:ok, 0}, &insert_chunk/2)
  end

  @spec to_row(DriverState.t(), DateTime.t()) :: [row()]
  defp to_row(
         %DriverState{coordinates: {lat, lng}, recorded_at: %DateTime{} = recorded_at} = state,
         now
       ) do
    [
      %{
        driver_id: state.driver_id,
        latitude: lat,
        longitude: lng,
        speed_kmh: state.speed_kmh,
        bearing_deg: state.bearing_deg,
        recorded_at: recorded_at,
        inserted_at: now
      }
    ]
  end

  defp to_row(_state, _now), do: []

  @spec insert_chunk([row()], outcome()) :: {:cont, outcome()} | {:halt, outcome()}
  defp insert_chunk(rows, {:ok, total}) do
    case insert_all(rows) do
      {:ok, count} -> {:cont, {:ok, total + count}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  @spec insert_all([row()]) :: {:ok, non_neg_integer()} | {:error, term()}
  defp insert_all(rows) do
    {count, nil} = Repo.insert_all(LocationPing, rows, on_conflict: :nothing)
    :ok = log_skipped(length(rows) - count)
    {:ok, count}
  rescue
    error -> {:error, error}
  end

  @spec log_skipped(non_neg_integer()) :: :ok
  defp log_skipped(0), do: :ok

  defp log_skipped(skipped) do
    Logger.debug("#{inspect(__MODULE__)} skipped #{skipped} duplicate ping(s)")
  end

  @spec record(t(), outcome()) :: t()
  defp record(state, {:ok, _count}), do: %{state | consecutive_failures: 0}

  defp record(state, {:error, reason}) do
    failures = state.consecutive_failures + 1
    Logger.error("#{inspect(__MODULE__)} flush failed (#{failures}x): #{inspect(reason)}")
    %{state | consecutive_failures: failures}
  end

  @spec schedule(t()) :: reference()
  defp schedule(%__MODULE__{interval_ms: interval, consecutive_failures: failures}) do
    Process.send_after(self(), :flush, interval * backoff(failures))
  end

  @spec backoff(non_neg_integer()) :: pos_integer()
  defp backoff(0), do: 1
  defp backoff(failures) when failures >= 3, do: @max_backoff
  defp backoff(failures), do: Integer.pow(2, failures)

  @spec interval_ms(term()) :: pos_integer()
  defp interval_ms(value) when is_integer(value) and value > 0, do: value
  defp interval_ms(_value), do: @default_interval_ms

  @spec chunk_size(term()) :: pos_integer()
  defp chunk_size(value) when is_integer(value) and value > 0, do: value
  defp chunk_size(_value), do: @default_chunk_size
end
