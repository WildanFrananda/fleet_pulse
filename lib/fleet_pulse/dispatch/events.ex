defmodule FleetPulse.Dispatch.Events do
  @moduledoc """
  Topic names and typed events for dispatch broadcasts.

  A driver's channel subscribes to `dispatch:driver:<id>` on join, so an
  assignment can be pushed to the device the instant it is made (PRD 5.5).

  The `dispatch:` prefix keeps these topics disjoint from the channel's own
  `driver:<id>` topic AND from the tracking context's `tracking:driver:<id>`.
  Three namespaces share one PubSub server; an unprefixed name would collide.
  """

  alias FleetPulse.Dispatch.Order
  alias FleetPulse.Types

  @pubsub FleetPulse.PubSub

  @typedoc "Every message a dispatch subscriber can receive."
  @type event :: {:order_assigned, Order.t()}

  @typedoc "Result of a subscription; mirrors `Phoenix.PubSub.subscribe/2`."
  @type subscribe_result :: :ok | {:error, {:already_registered, pid()}}

  @spec driver_topic(Types.id()) :: String.t()
  def driver_topic(driver_id), do: "dispatch:driver:#{driver_id}"

  @spec subscribe_driver(Types.id()) :: subscribe_result()
  def subscribe_driver(driver_id) do
    Phoenix.PubSub.subscribe(@pubsub, driver_topic(driver_id))
  end

  @spec broadcast(Types.id(), event()) :: :ok
  def broadcast(driver_id, event) do
    :ok = Phoenix.PubSub.broadcast(@pubsub, driver_topic(driver_id), event)
  end
end
