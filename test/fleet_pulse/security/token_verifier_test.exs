defmodule FleetPulse.Security.TokenVerifierTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias FleetPulse.IdentityJwks
  alias FleetPulse.Security.TokenVerifier

  @nowhere "http://127.0.0.1:1/.well-known/jwks.json"

  defp from, do: {self(), make_ref()}

  defp closed(url), do: %{keys: %{}, url: url, failures: 0, open_until: nil}

  defp open(url) do
    %{closed(url) | failures: 3, open_until: System.monotonic_time(:millisecond) + 5_000}
  end

  defp jwks_url, do: System.fetch_env!("IDENTITY_JWKS_URL")

  describe "a kid the cache does not hold" do
    test "is unavailable, not invalid, while the circuit is open" do
      state = open(@nowhere)

      assert {:reply, {:error, :identity_unavailable}, ^state} =
               TokenVerifier.handle_call({:key, "some-kid"}, from(), state)
    end

    test "is counted while the circuit is open, so a window's refusals are not invisible" do
      test_pid = self()
      handler = "test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:fleet_pulse, :token_verifier, :refused_while_open],
        fn name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      TokenVerifier.handle_call({:key, "some-kid"}, from(), open(@nowhere))

      assert_receive {:telemetry, [:fleet_pulse, :token_verifier, :refused_while_open],
                      %{count: 1}, %{}}
    end

    test "is unavailable, not invalid, when the fetch fails" do
      {reply, log} =
        with_log(fn ->
          TokenVerifier.handle_call({:key, "some-kid"}, from(), closed(@nowhere))
        end)

      assert {:reply, {:error, :identity_unavailable}, %{failures: 1}} = reply
      assert log =~ "did not return a JWKS"
    end

    test "is invalid when identity answered and published no such key" do
      assert {:reply, {:error, :invalid_token}, state} =
               TokenVerifier.handle_call({:key, "no-such-kid"}, from(), closed(jwks_url()))

      assert Map.has_key?(state.keys, IdentityJwks.kid())
    end
  end

  describe "a kid identity publishes" do
    test "is fetched and answered" do
      kid = IdentityJwks.kid()

      assert {:reply, {:ok, _jwk}, %{failures: 0, open_until: nil}} =
               TokenVerifier.handle_call({:key, kid}, from(), closed(jwks_url()))
    end

    test "is answered from the cache without asking identity again" do
      kid = IdentityJwks.kid()

      {:reply, {:ok, jwk}, cached} =
        TokenVerifier.handle_call({:key, kid}, from(), closed(jwks_url()))

      assert {:reply, {:ok, ^jwk}, _state} =
               TokenVerifier.handle_call({:key, kid}, from(), %{cached | url: @nowhere})
    end
  end
end
