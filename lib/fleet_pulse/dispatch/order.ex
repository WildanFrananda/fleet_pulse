defmodule FleetPulse.Dispatch.Order do
  @moduledoc """
  Ecto schema for a delivery order — a Pure Data Object (PODO).

  No behaviour: persistence and the assignment lifecycle live in the
  `FleetPulse.Dispatch` context. Here there is only the data shape and the
  rules for validating an incoming order.

  A pickup and a dropoff are each a coordinate pair; `weight_kg` is what the
  dispatch engine matches against driver capacity (PRD 5.5).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FleetPulse.Tracking.Driver
  alias FleetPulse.Types

  @typedoc "Order lifecycle state. Mirror of `@statuses` — keep them in sync."
  @type status :: :pending | :assigned | :picked_up | :delivered | :cancelled

  @typedoc """
  A persisted order.

  Every field is `| nil` because a bare `%Order{}` — before `cast/4` or a load
  — holds nil throughout. `driver:` is `NotLoaded` until preloaded, never nil
  once the association is fetched.
  """
  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Types.id() | nil,
          pickup_latitude: Types.latitude() | nil,
          pickup_longitude: Types.longitude() | nil,
          dropoff_latitude: Types.latitude() | nil,
          dropoff_longitude: Types.longitude() | nil,
          weight_kg: non_neg_integer() | nil,
          status: status() | nil,
          driver_id: Types.id() | nil,
          driver: Driver.t() | Ecto.Association.NotLoaded.t() | nil,
          assigned_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @typedoc "A changeset whose data is guaranteed to be an `t()`."
  @type changeset :: Ecto.Changeset.t(t())

  @statuses [:pending, :assigned, :picked_up, :delivered, :cancelled]

  @required_fields [
    :pickup_latitude,
    :pickup_longitude,
    :dropoff_latitude,
    :dropoff_longitude
  ]

  schema "orders" do
    field :pickup_latitude, :float
    field :pickup_longitude, :float
    field :dropoff_latitude, :float
    field :dropoff_longitude, :float
    field :weight_kg, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :assigned_at, :utc_datetime_usec

    belongs_to :driver, Driver

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The valid statuses — single source for validation, seeds, and UI choices.
  """
  @spec statuses() :: [status(), ...]
  def statuses, do: @statuses

  @doc """
  Changeset for creating a new, unassigned order.
  """
  @spec changeset(t(), map()) :: changeset()
  def changeset(%__MODULE__{} = order, attrs) do
    order
    |> cast(attrs, @required_fields ++ [:weight_kg])
    |> validate_required(@required_fields)
    |> validate_coordinate(:pickup_latitude, -90, 90)
    |> validate_coordinate(:pickup_longitude, -180, 180)
    |> validate_coordinate(:dropoff_latitude, -90, 90)
    |> validate_coordinate(:dropoff_longitude, -180, 180)
    |> validate_number(:weight_kg, greater_than_or_equal_to: 0, less_than_or_equal_to: 5_000)
    |> check_constraint(:pickup_latitude, name: :orders_pickup_latitude_range)
    |> check_constraint(:dropoff_latitude, name: :orders_dropoff_latitude_range)
  end

  @spec validate_coordinate(changeset(), atom(), number(), number()) :: changeset()
  defp validate_coordinate(changeset, field, min, max) do
    validate_number(changeset, field,
      greater_than_or_equal_to: min,
      less_than_or_equal_to: max
    )
  end
end
