defmodule FleetPulseWeb.AdminAuthTest do
  use FleetPulseWeb.ConnCase, async: true

  alias FleetPulse.Security.AccessClaims
  alias FleetPulseWeb.AdminAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])

    operator = %AccessClaims{
      principal_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      email: "operator@kinetix.test",
      role: "admin"
    }

    %{conn: conn, operator: operator}
  end

  describe "fetch_current_admin/2" do
    test "assigns the operator from a valid session", %{conn: conn, operator: operator} do
      conn =
        conn
        |> put_session("operator", Map.from_struct(operator))
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin.principal_id == operator.principal_id
      assert conn.assigns.current_admin.role == "admin"
    end

    test "assigns nil without a session", %{conn: conn} do
      conn = AdminAuth.fetch_current_admin(conn, [])
      assert conn.assigns.current_admin == nil
    end

    test "assigns nil for a session written in the old shape", %{conn: conn} do
      conn = conn |> put_session("operator", %{admin_id: 3}) |> AdminAuth.fetch_current_admin([])
      assert conn.assigns.current_admin == nil
    end

    test "assigns nil for a session whose role is not admin", %{conn: conn, operator: operator} do
      conn =
        conn
        |> put_session("operator", operator |> Map.from_struct() |> Map.put(:role, "seller"))
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin == nil
    end
  end

  describe "require_authenticated_admin/2" do
    test "lets an authenticated operator through", %{conn: conn, operator: operator} do
      conn =
        conn |> assign(:current_admin, operator) |> AdminAuth.require_authenticated_admin([])

      refute conn.halted
    end

    test "redirects an anonymous request to login", %{conn: conn} do
      conn = conn |> assign(:current_admin, nil) |> AdminAuth.require_authenticated_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/log_in"
    end
  end
end
