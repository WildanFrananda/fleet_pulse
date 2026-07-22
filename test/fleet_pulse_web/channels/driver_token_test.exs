defmodule FleetPulseWeb.DriverTokenTest do
  use ExUnit.Case, async: true

  alias FleetPulseWeb.DriverToken
  alias FleetPulseWeb.Endpoint

  test "a freshly signed token round-trips" do
    assert {:ok, 42} = DriverToken.verify(DriverToken.sign(42))
  end

  test "refuses a tampered token" do
    tampered = DriverToken.sign(42) <> "x"
    assert {:error, :invalid_token} = DriverToken.verify(tampered)
  end

  test "refuses a token minted with a different salt" do
    forged = Phoenix.Token.sign(Endpoint, "some other salt", 42)
    assert {:error, :invalid_token} = DriverToken.verify(forged)
  end

  test "refuses a token older than the maximum age" do
    stale = Phoenix.Token.sign(Endpoint, "driver socket", 42, signed_at: 0)
    assert {:error, :expired_token} = DriverToken.verify(stale)
  end

  test "refuses a validly signed payload that is not a driver id" do
    for payload <- [0, -1, "42", %{id: 42}] do
      signed = Phoenix.Token.sign(Endpoint, "driver socket", payload)
      assert {:error, :invalid_token} = DriverToken.verify(signed)
    end
  end

  test "refuses anything that is not a string" do
    for bad <- [nil, 42, %{}] do
      assert {:error, :invalid_token} = DriverToken.verify(bad)
    end
  end
end
