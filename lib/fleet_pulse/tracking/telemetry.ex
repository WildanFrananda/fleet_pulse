defmodule FleetPulse.Tracking.Telemetry do
  @moduledoc """
  Validation and normalisation of inbound GPS telemetry.

  Pure functions only — no processes, no database, no side effects. This logic
  lived inside `DriverState` until it needed a second caller: the driver
  channel must reject a malformed payload at the socket boundary, before
  anything enters the domain at all.

  Every bound enforced here mirrors a CHECK constraint in the
  `create_location_pings` migration. Those constraints are the specification;
  this module is their application-layer twin. Change one, change both.
  """

  alias FleetPulse.Types

  @typedoc """
  A validated, normalised telemetry payload.

  After `normalise/1` every key is present, every number is a float, and
  `recorded_at` carries microsecond precision — `Repo.insert_all/3` dumps
  `:utc_datetime_usec` through `check_usec!/2`, which raises on anything
  coarser and never pads it for you.
  """
  @type t :: %{
          latitude: Types.latitude(),
          longitude: Types.longitude(),
          speed_kmh: float() | nil,
          bearing_deg: float() | nil,
          recorded_at: DateTime.t()
        }

  @doc """
  Validates and normalises a raw telemetry payload.

  Unknown keys are discarded: the result is built fresh rather than merged
  into the input, so a device cannot smuggle extra fields into the domain.

  Returns `{:error, :invalid_telemetry}` rather than raising — a misbehaving
  device is an ordinary result to handle, not an exceptional condition.
  """
  @spec normalise(term()) :: {:ok, t()} | {:error, :invalid_telemetry}
  def normalise(%{recorded_at: %DateTime{} = recorded_at} = payload) do
    with {:ok, lat} <- latitude(Map.get(payload, :latitude)),
         {:ok, lng} <- longitude(Map.get(payload, :longitude)),
         {:ok, speed} <- speed_kmh(Map.get(payload, :speed_kmh)),
         {:ok, bearing} <- bearing_deg(Map.get(payload, :bearing_deg)) do
      {:ok,
       %{
         latitude: lat,
         longitude: lng,
         speed_kmh: speed,
         bearing_deg: bearing,
         recorded_at: with_usec(recorded_at)
       }}
    end
  end

  def normalise(_payload), do: {:error, :invalid_telemetry}

  @doc """
  Builds telemetry from raw socket params, where keys are strings and
  `recorded_at` is an ISO 8601 string.

  Keys are mapped explicitly, never with `String.to_atom/1`: atoms are not
  garbage collected, so converting attacker-controlled strings is a memory
  exhaustion vector.

  This lives in the domain rather than the channel so the wire-format rules
  sit beside the value rules they feed, and so both are unit-testable without
  a socket.
  """
  @spec from_params(term()) :: {:ok, t()} | {:error, :invalid_telemetry}
  def from_params(params) when is_map(params) do
    with {:ok, recorded_at} <- parse_datetime(Map.get(params, "recorded_at")) do
      normalise(%{
        latitude: Map.get(params, "latitude"),
        longitude: Map.get(params, "longitude"),
        speed_kmh: Map.get(params, "speed_kmh"),
        bearing_deg: Map.get(params, "bearing_deg"),
        recorded_at: recorded_at
      })
    end
  end

  def from_params(_params), do: {:error, :invalid_telemetry}

  @spec latitude(term()) :: {:ok, Types.latitude()} | {:error, :invalid_telemetry}
  defp latitude(value) when is_number(value) and value >= -90 and value <= 90,
    do: {:ok, value * 1.0}

  defp latitude(_value), do: {:error, :invalid_telemetry}

  @spec longitude(term()) :: {:ok, Types.longitude()} | {:error, :invalid_telemetry}
  defp longitude(value) when is_number(value) and value >= -180 and value <= 180,
    do: {:ok, value * 1.0}

  defp longitude(_value), do: {:error, :invalid_telemetry}

  @spec speed_kmh(term()) :: {:ok, float() | nil} | {:error, :invalid_telemetry}
  defp speed_kmh(nil), do: {:ok, nil}
  defp speed_kmh(value) when is_number(value) and value >= 0, do: {:ok, value * 1.0}
  defp speed_kmh(_value), do: {:error, :invalid_telemetry}

  @spec bearing_deg(term()) :: {:ok, float() | nil} | {:error, :invalid_telemetry}
  defp bearing_deg(nil), do: {:ok, nil}

  defp bearing_deg(value) when is_number(value) and value >= 0 and value < 360,
    do: {:ok, value * 1.0}

  defp bearing_deg(_value), do: {:error, :invalid_telemetry}

  @spec with_usec(DateTime.t()) :: DateTime.t()
  defp with_usec(%DateTime{microsecond: {_value, 6}} = recorded_at), do: recorded_at

  defp with_usec(%DateTime{microsecond: {value, _precision}} = recorded_at),
    do: %{recorded_at | microsecond: {value, 6}}

  @spec parse_datetime(term()) :: {:ok, DateTime.t()} | {:error, :invalid_telemetry}
  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _utc_offset} -> {:ok, datetime}
      {:error, _reason} -> {:error, :invalid_telemetry}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_telemetry}
end
