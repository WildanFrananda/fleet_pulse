defmodule FleetPulse.Servers.ShippingServer do
  @moduledoc """
  gRPC Server Handler for Shipping Fee Estimation (PRD shipping_courier_selection_prd).

  This module existed but was not a gRPC server: it declared no service, so it could not be
  registered on the endpoint, and `shipping.v1` was advertised in the proto directory while
  nothing served it. It also returned bare maps where the wire needs protobuf structs.
  """

  use GRPC.Server, service: FleetPulse.Proto.Shipping.V1.ShippingService.Service

  require Logger

  alias FleetPulse.Proto.Common.V1.Money
  alias FleetPulse.Proto.Shipping.V1.CourierOption
  alias FleetPulse.Proto.Shipping.V1.EstimateShippingOptionsResponse
  alias FleetPulse.Shipping

  @spec estimate_shipping_options(
          FleetPulse.Proto.Shipping.V1.EstimateShippingOptionsRequest.t(),
          GRPC.Server.Stream.t()
        ) :: EstimateShippingOptionsResponse.t()
  def estimate_shipping_options(request, _stream) do
    origin = %{
      latitude: request.origin.latitude,
      longitude: request.origin.longitude
    }

    destination = %{
      latitude: request.destination.latitude,
      longitude: request.destination.longitude
    }

    Logger.info(
      "[FleetPulse gRPC Server] EstimateShippingOptions for merchant " <>
        inspect(request.merchant_principal_id)
    )

    res =
      Shipping.calculate_options(
        origin,
        destination,
        request.total_weight_grams / 1000,
        request.merchant_principal_id
      )

    options =
      Enum.map(res.options, fn opt ->
        %CourierOption{
          service_tier: opt.service_tier,
          service_name: opt.service_name,
          distance_km: opt.distance_km,
          base_shipping_fee: %Money{
            amount_minor: round(opt.base_shipping_fee * 100),
            currency: "IDR"
          },
          estimated_delivery_time: opt.estimated_delivery_time,
          is_available: opt.is_available,
          unavailable_reason: opt.unavailable_reason || ""
        }
      end)

    %EstimateShippingOptionsResponse{
      distance_km: res.distance_km,
      options: options
    }
  end
end
