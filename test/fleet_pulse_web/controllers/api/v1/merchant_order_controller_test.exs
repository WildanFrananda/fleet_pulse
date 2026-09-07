defmodule FleetPulseWeb.Api.V1.MerchantOrderControllerTest do
  use FleetPulseWeb.ConnCase, async: true

  @merchant_principal "3c9a77b1-58de-4a01-8f2e-6d4b19c0a8f3"

  setup %{conn: conn} do
    conn =
      conn
      |> authenticate(role: "seller", sub: @merchant_principal)
      |> put_req_header("accept", "application/json")

    %{conn: conn}
  end

  describe "POST /api/v1/merchant/orders" do
    test "creates an order successfully with valid params", %{conn: conn} do
      params = %{
        "order" => %{
          "pickup_latitude" => -6.2000,
          "pickup_longitude" => 106.8100,
          "dropoff_latitude" => -6.2100,
          "dropoff_longitude" => 106.8200,
          "weight_kg" => 12,
          "merchant_principal_id" => "9f1d4a3e-1c62-4d0a-9a7b-2f5c8e0b41d7"
        }
      }

      conn = post(conn, ~p"/api/v1/merchant/orders", params)
      body = json_response(conn, 201)

      assert %{"id" => id, "status" => "pending", "merchant_principal_id" => @merchant_principal} = body["data"]
      assert body["data"]["pickup"]["latitude"] == -6.2000
      assert body["data"]["dropoff"]["longitude"] == 106.8200
      assert is_integer(id)
    end

    test "returns 422 unprocessable_entity when required coordinates are missing", %{conn: conn} do
      params = %{
        "order" => %{
          "weight_kg" => 10
        }
      }

      conn = post(conn, ~p"/api/v1/merchant/orders", params)
      body = json_response(conn, 422)

      assert %{"errors" => errors} = body
      assert errors["pickup_latitude"] != nil
      assert errors["dropoff_latitude"] != nil
    end

    test "returns 401 unauthorized without a token" do
      params = %{
        "order" => %{
          "pickup_latitude" => -6.2000,
          "pickup_longitude" => 106.8100,
          "dropoff_latitude" => -6.2100,
          "dropoff_longitude" => 106.8200,
          "weight_kg" => 5
        }
      }

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/merchant/orders", params)

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end
end
