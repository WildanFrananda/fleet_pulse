defmodule FleetPulse.Tracking.Events do
  @moduledoc """
  Topic names and typed events for tracking broadcasts.

  Every change is published to TWO topics, deliberately:

    * `"drivers"` — the whole fleet. What the dispatch map subscribes to.
    * `"driver:<id>"` — a single driver. What a detail view subscribes to.

  Publishing twice costs one extra in-node message send, which is close to
  free. The alternative — a single fleet-wide topic — would force a detail
  page to receive all 2000 updates per second (PRD target) and discard the
  9999 drivers it does not care about. Filtering is far more expensive than
  sending.
  """

  alias FleetPulse.Tracking.DriverState
  alias FleetPulse.Types
  alias Phoenix.PubSub

  @pubsub FleetPulse.PubSub
  @fleet_topic "drivers"

  @typedoc "Every message a tracking subscriber can receive."
  @type event :: {:driver_updated, DriverState.t()} | {:driver_stopped, Types.id()}

  @typedoc """
  Result of a subscription.

  `Phoenix.PubSub.subscribe/2` reports `{:error, {:already_registered, pid}}`
  when the calling process already holds a conflicting registry entry for the
  topic.
  """
  @type subscribe_result :: :ok | {:error, {:already_registered, pid()}}

  @spec fleet_topic() :: String.t()
  def fleet_topic, do: @fleet_topic

  @spec driver_topic(Types.id()) :: String.t()
  def driver_topic(driver_id), do: "driver:#{driver_id}"

  @spec subscribe_fleet() :: subscribe_result()
  def subscribe_fleet, do: PubSub.subscribe(@pubsub, @fleet_topic)

  @spec subscribe_driver(Types.id()) :: subscribe_result()
  def subscribe_driver(driver_id) do
    PubSub.subscribe(@pubsub, driver_topic(driver_id))
  end

  @spec unsubscribe_fleet() :: :ok
  def unsubscribe_fleet, do: PubSub.unsubscribe(@pubsub, @fleet_topic)

  @spec unsubscribe_driver(Types.id()) :: :ok
  def unsubscribe_driver(driver_id) do
    PubSub.unsubscribe(@pubsub, driver_topic(driver_id))
  end

  @doc """
  Publishes an event to both the fleet topic and the driver's own topic.
  """
  @spec broadcast(Types.id(), event()) :: :ok
  def broadcast(driver_id, event) do
    :ok = PubSub.broadcast(@pubsub, @fleet_topic, event)
    :ok = PubSub.broadcast(@pubsub, driver_topic(driver_id), event)
  end
end
