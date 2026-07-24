defmodule FleetPulseWeb.AdminSessionControllerTest do
  use FleetPulseWeb.ConnCase, async: true

  import FleetPulse.AccountsFixtures

  setup do
    %{admin: admin_fixture()}
  end

  describe "GET /admin/log_in" do
    test "renders the login form", %{conn: conn} do
      assert html_response(get(conn, ~p"/admin/log_in"), 200) =~ "Log in"
    end
  end

  describe "POST /admin/log_in" do
    test "logs in with valid credentials", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admin/log_in", %{
          "admin" => %{"email" => admin.email, "password" => "supersecret123"}
        })

      assert get_session(conn, "admin_id") == admin.id
      assert redirected_to(conn) == ~p"/dispatch"
    end

    test "rejects a wrong password without a session", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admin/log_in", %{
          "admin" => %{"email" => admin.email, "password" => "wrong"}
        })

      assert html_response(conn, 200) =~ "Invalid email or password"
      refute get_session(conn, "admin_id")
    end
  end

  describe "DELETE /admin/log_out" do
    test "clears the session", %{conn: conn, admin: admin} do
      conn = conn |> log_in_admin(admin) |> delete(~p"/admin/log_out")

      refute get_session(conn, "admin_id")
      assert redirected_to(conn) == ~p"/"
    end
  end
end
