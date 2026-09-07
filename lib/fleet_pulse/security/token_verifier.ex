defmodule FleetPulse.Security.TokenVerifier do
  @moduledoc """
  Verifies identity's access tokens against its published JWKS.
  """

  use GenServer

  require Logger

  alias FleetPulse.Security.AccessClaims

  @type error :: :invalid_token | :malformed_claims | :identity_unavailable

  @typep state :: %{
           keys: %{String.t() => JOSE.JWK.t()},
           url: String.t(),
           failures: non_neg_integer(),
           open_until: integer() | nil
         }

  @typep freshness :: :fetched | :unavailable

  @failures_before_open 3
  @open_for_ms 5_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec verify_access(String.t()) :: {:ok, AccessClaims.t()} | {:error, error()}
  def verify_access(token) when is_binary(token) do
    with {:ok, kid} <- kid_of(token),
         {:ok, jwk} <- key(kid),
         {true, %JOSE.JWT{fields: claims}, _jws} <- JOSE.JWT.verify_strict(jwk, ["RS256"], token),
         :ok <- check_claims(claims) do
      AccessClaims.from_payload(claims)
    else
      {:error, reason} -> {:error, reason}
      _refused -> {:error, :invalid_token}
    end
  end

  def verify_access(_token), do: {:error, :invalid_token}

  @spec refresh!() :: non_neg_integer()
  def refresh!, do: GenServer.call(__MODULE__, :refresh, 15_000)


  @impl GenServer
  def init(_opts) do
    {:ok, %{keys: %{}, url: require_env("IDENTITY_JWKS_URL"), failures: 0, open_until: nil}}
  end

  @impl GenServer
  def handle_call({:key, kid}, _from, state) do
    case Map.fetch(state.keys, kid) do
      {:ok, jwk} ->
        {:reply, {:ok, jwk}, state}

      :error ->
        {freshness, state} = fetch(state)

        case Map.fetch(state.keys, kid) do
          {:ok, jwk} -> {:reply, {:ok, jwk}, state}
          :error -> {:reply, {:error, miss(freshness)}, state}
        end
    end
  end

  @impl GenServer
  def handle_call(:refresh, _from, state) do
    {_freshness, state} = fetch(state)
    {:reply, map_size(state.keys), state}
  end

  @spec miss(freshness()) :: :invalid_token | :identity_unavailable
  defp miss(:fetched), do: :invalid_token
  defp miss(:unavailable), do: :identity_unavailable

  @spec fetch(state()) :: {freshness(), state()}
  defp fetch(state), do: fetch(state, System.monotonic_time(:millisecond))

  @spec fetch(state(), integer()) :: {freshness(), state()}
  defp fetch(%{open_until: open_until} = state, now)
       when is_integer(open_until) and now < open_until do
    :telemetry.execute([:fleet_pulse, :token_verifier, :refused_while_open], %{count: 1}, %{})
    {:unavailable, state}
  end

  defp fetch(state, _now) do
    case get_jwks(state.url) do
      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}} when is_list(keys) ->
        {:fetched, %{state | keys: import_keys(keys), failures: 0, open_until: nil}}

      other ->
        {:unavailable, fetch_failed(state, System.monotonic_time(:millisecond), other)}
    end
  end

  @spec get_jwks(String.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  defp get_jwks(url) do
    Req.get(url, retry: false, connect_options: [timeout: 2_000], request_timeout: 3_000)
  rescue
    error -> {:error, error}
  end

  @spec fetch_failed(state(), integer(), term()) :: state()
  defp fetch_failed(%{failures: failures} = state, now, other)
       when failures + 1 >= @failures_before_open do
    Logger.error(
      "[TokenVerifier] #{state.url} did not return a JWKS: #{inspect(other)} — " <>
        "asking no further for #{@open_for_ms}ms"
    )

    %{state | failures: @failures_before_open, open_until: now + @open_for_ms}
  end

  defp fetch_failed(state, _now, other) do
    Logger.error("[TokenVerifier] #{state.url} did not return a JWKS: #{inspect(other)}")
    %{state | failures: state.failures + 1}
  end

  @spec import_keys([map()]) :: %{String.t() => JOSE.JWK.t()}
  defp import_keys(keys) do
    keys
    |> Enum.filter(fn jwk ->
      Map.get(jwk, "alg", "RS256") == "RS256" and is_binary(Map.get(jwk, "kid"))
    end)
    |> Map.new(fn jwk -> {jwk["kid"], JOSE.JWK.from_map(jwk)} end)
  end

  @spec key(String.t()) :: {:ok, JOSE.JWK.t()} | {:error, error()}
  defp key(kid), do: GenServer.call(__MODULE__, {:key, kid}, 15_000)

  @spec kid_of(String.t()) :: {:ok, String.t()} | {:error, error()}
  defp kid_of(token) do
    case JOSE.JWT.peek_protected(token) do
      %JOSE.JWS{fields: %{"kid" => kid}} when is_binary(kid) and kid != "" -> {:ok, kid}
      _no_kid -> {:error, :invalid_token}
    end
  rescue
    _unparseable -> {:error, :invalid_token}
  end

  @spec check_claims(map()) :: :ok | {:error, error()}
  defp check_claims(claims) do
    now = System.system_time(:second)

    cond do
      claims["iss"] != require_env("JWT_ISSUER") -> {:error, :invalid_token}
      not audience_matches?(claims["aud"]) -> {:error, :invalid_token}
      claims["token_use"] != "access" -> {:error, :invalid_token}
      not is_integer(claims["exp"]) or claims["exp"] <= now -> {:error, :invalid_token}
      true -> :ok
    end
  end

  @spec audience_matches?(term()) :: boolean()
  defp audience_matches?(aud) do
    expected = require_env("JWT_AUDIENCE")

    case aud do
      ^expected -> true
      list when is_list(list) -> expected in list
      _other -> false
    end
  end

  @spec require_env(String.t()) :: String.t()
  defp require_env(name) do
    System.get_env(name) || raise "#{name} is required and has no default."
  end
end
