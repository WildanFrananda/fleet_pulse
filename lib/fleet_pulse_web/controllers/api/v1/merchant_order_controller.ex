defmodule FleetPulseWeb.Api.V1.MerchantOrderController do
  @moduledoc """
  API controller for merchant order creation and management.
  """

  use FleetPulseWeb, :controller

  alias FleetPulse.Dispatch
  alias FleetPulse.Dispatch.Order

  @doc """
  Creates a new order submitted by an authenticated merchant.

  The merchant the order belongs to is taken from the verified token and overwrites anything the
  body carried. It used to be read straight out of `order_params`, so an authenticated caller
  could file orders against any merchant it cared to name — and the caller's own identity was
  never consulted at all.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"order" => order_params}) when is_map(order_params) do
    caller = conn.assigns.current_caller
    attrs = Map.put(order_params, "merchant_principal_id", caller.principal_id)

    case Dispatch.create_order(attrs) do
      {:ok, %Order{} = order} ->
        conn
        |> put_status(:created)
        |> json(%{data: serialize(order)})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  def create(conn, _invalid_params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload", message: "Payload must include an 'order' object."})
  end

  @spec serialize(Order.t()) :: map()
  defp serialize(%Order{} = order) do
    %{
      id: order.id,
      status: order.status,
      merchant_principal_id: order.merchant_principal_id,
      weight_kg: order.weight_kg,
      driver_id: order.driver_id,
      pickup: %{latitude: order.pickup_latitude, longitude: order.pickup_longitude},
      dropoff: %{latitude: order.dropoff_latitude, longitude: order.dropoff_longitude},
      inserted_at: order.inserted_at
    }
  end

  @spec translate_errors(Ecto.Changeset.t()) :: map()
  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
