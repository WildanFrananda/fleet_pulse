defmodule FleetPulse.Types do
  @moduledoc """
  Shared type dictionary for the entire FleetPulse domain.

  Analogous to the global `types.ts`: each context (Tracking, Dispatch)
  `aliases`/`imports` types from here for a single, consistent definition.
  """

  @typedoc "Positive integer based entity ID (driver_id, order_id, etc)."
  @type id :: pos_integer()

  @typedoc "Standard result tuple. Always return this, do not raise for flow control."
  @type result(inner) :: {:ok, inner} | {:error, reason()}

  @typedoc "Explicit (atomic) or structured error reasons."
  @type reason :: atom() | {atom(), term()}

  @typedoc "Latitude, -90.0..90.0"
  @type latitude :: float()

  @typedoc "Longitude, -180.0..180.0"
  @type longitude :: float()

  @typedoc "GPS coordinate pair."
  @type coordinates :: {latitude(), longitude()}

  @typedoc "Driver availability status (see PRD 5.2)."
  @type driver_status :: :online | :busy | :offline
end
