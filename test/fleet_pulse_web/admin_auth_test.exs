defmodule FleetPulseWeb.AdminAuthTest do
  use FleetPulseWeb.ConnCase, async: true

  import FleetPulse.AccountsFixtures

  alias FleetPulseWeb.AdminAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])

    %{conn: conn, admin: admin_fixture()}
  end

  describe "fetch_current_admin/2" do
    test "assigns the admin from a valid session", %{conn: conn, admin: admin} do
      conn = conn |> put_session("admin_id", admin.id) |> AdminAuth.fetch_current_admin([])
      assert conn.assigns.current_admin.id == admin.id
    end

    test "assigns nil without a session", %{conn: conn} do
      conn = AdminAuth.fetch_current_admin(conn, [])
      assert conn.assigns.current_admin == nil
    end

    test "assigns nil when the id points at nobody", %{conn: conn} do
      conn = conn |> put_session("admin_id", 999_999_999) |> AdminAuth.fetch_current_admin([])
      assert conn.assigns.current_admin == nil
    end
  end

  describe "require_authenticated_admin/2" do
    test "lets an authenticated admin through", %{conn: conn, admin: admin} do
      conn = conn |> assign(:current_admin, admin) |> AdminAuth.require_authenticated_admin([])
      refute conn.halted
    end

    test "redirects an anonymous request to login", %{conn: conn} do
      conn = conn |> assign(:current_admin, nil) |> AdminAuth.require_authenticated_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/log_in"
    end
  end
end
