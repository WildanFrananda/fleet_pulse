defmodule FleetPulseWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use FleetPulseWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias FleetPulse.IdentityJwks
  alias FleetPulse.Security.AccessClaims

  using do
    quote do
      # The default endpoint for testing
      @endpoint FleetPulseWeb.Endpoint

      use FleetPulseWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import FleetPulseWeb.ConnCase
    end
  end

  @doc """
  Puts a verified operator into the test session, so a browser request arrives authenticated.

  The session now carries claims, not a local admin id — there is no admins table to point at.
  """
  @spec log_in_operator(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def log_in_operator(conn, overrides \\ []) do
    claims = %AccessClaims{
      principal_id: Keyword.get(overrides, :principal_id, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
      email: Keyword.get(overrides, :email, "operator@kinetix.test"),
      role: Keyword.get(overrides, :role, "admin")
    }

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("operator", Map.from_struct(claims))
  end

  @doc """
  Sets an `Authorization` header carrying a freshly minted identity access token.
  """
  @spec authenticate(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def authenticate(conn, overrides \\ []) do
    {header, value} = IdentityJwks.bearer(IdentityJwks.token(overrides))
    Plug.Conn.put_req_header(conn, header, value)
  end

  setup tags do
    FleetPulse.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
