defmodule FleetPulseWeb.Api.V1.ShippingController do
  @moduledoc """
  REST API Controller for Shipping Rates & Courier Options (PRD shipping_courier_selection_prd).
  """

  use FleetPulseWeb, :controller

  alias FleetPulse.Shipping

  def options(conn, %{
        "origin" => %{"latitude" => o_lat, "longitude" => o_lng},
        "destination" => %{"latitude" => d_lat, "longitude" => d_lng},
        "total_weight_kg" => weight
      } = params) do
    o_lat_f = to_float(o_lat)
    o_lng_f = to_float(o_lng)
    d_lat_f = to_float(d_lat)
    d_lng_f = to_float(d_lng)
    weight_f = to_float(weight)
    merchant_principal_id = params["merchant_principal_id"]

    origin = %{latitude: o_lat_f, longitude: o_lng_f}
    destination = %{latitude: d_lat_f, longitude: d_lng_f}

    result = Shipping.calculate_options(origin, destination, weight_f, merchant_principal_id)
    json(conn, result)
  end

  def options(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{
      error: "UNPROCESSABLE_ENTITY",
      message: "Required parameters: origin (latitude, longitude), destination (latitude, longitude), total_weight_kg"
    })
  end

  defp to_float(val) when is_float(val), do: val
  defp to_float(val) when is_integer(val), do: val / 1.0
  defp to_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end
  defp to_float(_), do: 0.0
end
