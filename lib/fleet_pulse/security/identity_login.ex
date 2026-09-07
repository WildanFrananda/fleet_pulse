defmodule FleetPulse.Security.IdentityLogin do
  @moduledoc """
  Exchanges an operator's email and password for identity's tokens.

  This service never sees a stored credential and never compares one. The form posts here, the
  password is forwarded once to identity over the internal network, and what comes back is a
  token this service then verifies with the same verifier every other route uses.

  What this replaces: `FleetPulse.Accounts`, `FleetPulse.Accounts.Admin` and the local `admins`
  table — a second password store, with its own bcrypt cost, its own reset story that was never
  written, and its own answer to who somebody is.
  """

  require Logger

  alias FleetPulse.Security.AccessClaims
  alias FleetPulse.Security.TokenVerifier

  @type error ::
          :invalid_credentials
          | :not_an_operator
          | :two_factor_required
          | :rate_limited
          | :identity_unavailable

  @spec log_in(String.t(), String.t()) :: {:ok, AccessClaims.t()} | {:error, error()}
  def log_in(email, password) when is_binary(email) and is_binary(password) do
    case post_login(email, password) do
      {:ok, %Req.Response{status: 201, body: %{"accessToken" => token}}} ->
        verify(token)

      {:ok, %Req.Response{status: 200, body: %{"accessToken" => token}}} ->
        verify(token)

      {:ok, %Req.Response{status: 200, body: %{"mfaRequired" => true}}} ->
        {:error, :two_factor_required}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status}} when status in 400..499 ->
        {:error, :invalid_credentials}

      other ->
        unavailable(other)
    end
  end

  def log_in(_email, _password), do: {:error, :invalid_credentials}

  @spec post_login(String.t(), String.t()) :: {:ok, Req.Response.t()} | {:error, term()}
  defp post_login(email, password) do
    base = System.get_env("IDENTITY_HTTP_URL") || raise "IDENTITY_HTTP_URL is required."

    Req.post(base <> "/api/v1/auth/login",
      json: %{email: email, password: password},
      headers: correlation_headers(),
      retry: false,
      connect_options: [timeout: 2_000],
      receive_timeout: 8_000,
      request_timeout: 10_000
    )
  end

  @spec correlation_headers() :: [{String.t(), String.t()}]
  defp correlation_headers do
    case Logger.metadata()[:request_id] do
      id when is_binary(id) and id != "" -> [{"x-request-id", id}]
      _absent -> []
    end
  end

  @spec verify(String.t()) :: {:ok, AccessClaims.t()} | {:error, error()}
  defp verify(token) do
    with {:ok, %AccessClaims{} = claims} <- TokenVerifier.verify_access(token),
         :ok <- operator?(claims) do
      {:ok, claims}
    else
      {:error, :not_an_operator} = refusal ->
        refusal

      {:error, reason} ->
        Logger.error(
          "[IdentityLogin] identity issued a token this service refused: #{inspect(reason)}"
        )

        {:error, :identity_unavailable}
    end
  end

  @spec operator?(AccessClaims.t()) :: :ok | {:error, :not_an_operator}
  defp operator?(%AccessClaims{role: "admin"}), do: :ok
  defp operator?(_claims), do: {:error, :not_an_operator}

  @spec unavailable(term()) :: {:error, :identity_unavailable}
  defp unavailable(other) do
    Logger.error("[IdentityLogin] identity did not answer the login: #{inspect(other)}")
    {:error, :identity_unavailable}
  end
end
