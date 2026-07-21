defmodule FleetPulse.Tracking.LocationPing do
  @moduledoc """
  Ecto schema for a single GPS telemetry ping — PODO append-only.

  Rows in this table are never updated. They are written in batches by the batcher and read during driver process rehydration.

  WARNING: The primary write path is `Repo.insert_all/3`, which
  **skips the changeset entirely**. Therefore, `changeset/2` below is NOT
  the only guard — the value limit must be present as a CHECK constraint in the
  migration. See the `insert_all` note below.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias FleetPulse.Tracking.Driver
  alias FleetPulse.Types

  @typedoc """
  One persistent telemetry ping.

  Note `driver:` — `belongs_to` generates TWO fields: `driver_id`
  (scalar value) and `driver` (association). Before preloading, the contents
  `%Ecto.Association.NotLoaded{}`, not `nil`. Skipping this variant is
  The second most common typespec flaw in Ecto projects after forgetting `| nil`.
  """
  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Types.id() | nil,
          driver_id: Types.id() | nil,
          driver: Driver.t() | NotLoaded.t() | nil,
          latitude: Types.latitude() | nil,
          longitude: Types.longitude() | nil,
          speed_kmh: float() | nil,
          bearing_deg: float() | nil,
          recorded_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @typedoc "Changeset whose data is guaranteed to be of type `t()`."
  @type changeset :: Ecto.Changeset.t(t())

  @required_fields [:driver_id, :latitude, :longitude, :recorded_at]
  @optional_fields [:speed_kmh, :bearing_deg]

  schema "location_pings" do
    belongs_to :driver, Driver

    field :latitude, :float
    field :longitude, :float
    field :speed_kmh, :float
    field :bearing_deg, :float
    field :recorded_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Changeset for unit insertion and incoming payload validation.

  Used Channel (Stage 4) to validate ping from BEFORE device
  go into memory. The batch path uses `Repo.insert_all/3` and does not pass through
  here — see warning in `@moduledoc`.
  """
  @spec changeset(t(), map()) :: changeset()
  def changeset(%__MODULE__{} = ping, attrs) do
    ping
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_number(:speed_kmh, greater_than_or_equal_to: 0)
    |> validate_number(:bearing_deg, greater_than_or_equal_to: 0, less_than: 360)
    |> assoc_constraint(:driver)
    |> check_constraint(:latitude, name: :location_pings_latitude_range)
    |> check_constraint(:longitude, name: :location_pings_longitude_range)
  end
end
