defmodule JidoCode.AuthProviders.BrokerHandoff do
  @moduledoc """
  Validates broker-issued JWT handoffs against provider trust settings.
  """

  # covers: auth.provider_broker_handoff.broker_jwt_validation
  # covers: auth.provider_broker_handoff.issuer_and_audience_validation
  # covers: auth.provider_broker_handoff.nonce_binding
  # covers: auth.provider_broker_handoff.nonce_replay_protection

  alias JidoCode.AuthProviders.{BrokerNonceStore, ProviderConfig}

  @allowed_algs ~w(RS256 RS384 RS512 ES256 ES384 ES512 EdDSA)

  @type typed_error :: %{
          error_type: String.t(),
          message: String.t(),
          recovery_instruction: String.t()
        }

  @type validated_claims :: %{
          issuer: String.t(),
          audience: [String.t()],
          nonce: String.t(),
          provider: String.t(),
          provider_host: String.t(),
          expires_at: DateTime.t(),
          claims: map()
        }

  @doc """
  Validates a broker handoff token against a provider config and expected state.
  """
  @spec validate(String.t(), ProviderConfig.t() | map(), map(), keyword()) ::
          {:ok, validated_claims()} | {:error, typed_error()}
  def validate(token, provider_config, expected_state, opts \\ [])

  def validate(token, provider_config, expected_state, opts)
      when is_binary(token) and is_map(provider_config) and is_map(expected_state) and is_list(opts) do
    with {:ok, jwks} <- resolve_jwks(provider_config, opts),
         {:ok, claims} <- verify_signature(token, jwks),
         {:ok, expires_at} <- parse_expiry(Map.get(claims, "exp")),
         :ok <- validate_issuer(claims, provider_config),
         :ok <- validate_audience(claims, provider_config),
         :ok <- validate_state_binding(claims, expected_state),
         :ok <-
           ensure_not_expired(expires_at, Keyword.get(opts, :now, DateTime.utc_now() |> DateTime.truncate(:second))),
         :ok <- consume_nonce(Map.get(claims, "nonce"), expires_at) do
      {:ok,
       %{
         issuer: Map.get(claims, "iss"),
         audience: normalize_audience(Map.get(claims, "aud")),
         nonce: Map.get(claims, "nonce"),
         provider: Map.get(claims, "provider"),
         provider_host: Map.get(claims, "provider_host"),
         expires_at: expires_at,
         claims: claims
       }}
    end
  end

  def validate(_token, _provider_config, _expected_state, _opts) do
    {:error,
     typed_error(
       "broker_handoff_invalid",
       "Broker handoff token is invalid.",
       "Restart provider sign-in and retry the handoff."
     )}
  end

  defp resolve_jwks(provider_config, opts) do
    resolver =
      Keyword.get_lazy(opts, :jwks_resolver, fn ->
        Application.get_env(:jido_code, :provider_auth_broker_jwks_resolver, &default_jwks_resolver/1)
      end)

    if is_function(resolver, 1) do
      case resolver.(provider_config) do
        {:ok, %{"keys" => keys}} when is_list(keys) and keys != [] ->
          {:ok, keys}

        {:ok, %{keys: keys}} when is_list(keys) and keys != [] ->
          {:ok, keys}

        {:error, _reason} ->
          {:error,
           typed_error(
             "broker_jwks_unavailable",
             "Broker signing keys could not be loaded.",
             "Verify broker JWKS availability and retry the handoff."
           )}

        _other ->
          {:error,
           typed_error(
             "broker_jwks_unavailable",
             "Broker signing keys could not be loaded.",
             "Verify broker JWKS availability and retry the handoff."
           )}
      end
    else
      {:error,
       typed_error(
         "broker_jwks_unavailable",
         "Broker signing keys could not be loaded.",
         "Verify broker JWKS availability and retry the handoff."
       )}
    end
  end

  defp default_jwks_resolver(provider_config) do
    broker_base_url = Map.get(provider_config, :broker_base_url) || Map.get(provider_config, "broker_base_url")

    with broker_base_url when is_binary(broker_base_url) <- normalize_optional_string(broker_base_url),
         jwks_url = "#{String.trim_trailing(broker_base_url, "/")}/.well-known/jwks.json",
         {:ok, response} <- Req.get(jwks_url) do
      case response.status do
        status when status in 200..299 ->
          {:ok, response.body}

        _other ->
          {:error, :unexpected_status}
      end
    else
      _ -> {:error, :jwks_fetch_failed}
    end
  end

  defp verify_signature(token, jwks) do
    verification =
      Enum.reduce_while(jwks, :invalid, fn jwk_map, _acc ->
        case JOSE.JWT.verify_strict(JOSE.JWK.from_map(jwk_map), @allowed_algs, token) do
          {true, %JOSE.JWT{fields: claims}, _jws} when is_map(claims) ->
            {:halt, {:ok, claims}}

          _other ->
            {:cont, :invalid}
        end
      end)

    case verification do
      {:ok, claims} ->
        {:ok, claims}

      _other ->
        {:error,
         typed_error(
           "broker_handoff_invalid",
           "Broker handoff signature could not be verified.",
           "Restart provider sign-in and retry the handoff."
         )}
    end
  end

  defp validate_issuer(claims, provider_config) do
    expected_issuer =
      provider_config
      |> Map.get(:broker_issuer, Map.get(provider_config, "broker_issuer"))
      |> normalize_optional_string()

    actual_issuer = claims |> Map.get("iss") |> normalize_optional_string()

    if expected_issuer != nil and actual_issuer == expected_issuer do
      :ok
    else
      {:error,
       typed_error(
         "broker_handoff_invalid_issuer",
         "Broker handoff issuer is invalid.",
         "Verify the broker issuer configuration and retry the handoff."
       )}
    end
  end

  defp validate_audience(claims, provider_config) do
    expected_audience =
      provider_config
      |> Map.get(:broker_audience, Map.get(provider_config, "broker_audience"))
      |> normalize_optional_string()

    audiences = normalize_audience(Map.get(claims, "aud"))

    if expected_audience != nil and expected_audience in audiences do
      :ok
    else
      {:error,
       typed_error(
         "broker_handoff_invalid_audience",
         "Broker handoff audience is invalid.",
         "Verify the broker audience configuration and retry the handoff."
       )}
    end
  end

  defp validate_state_binding(claims, expected_state) do
    expected_nonce = expected_state |> Map.get(:nonce, Map.get(expected_state, "nonce")) |> normalize_optional_string()

    expected_provider =
      expected_state |> Map.get(:provider, Map.get(expected_state, "provider")) |> normalize_optional_string()

    expected_provider_host =
      expected_state |> Map.get(:provider_host, Map.get(expected_state, "provider_host")) |> normalize_optional_string()

    actual_nonce = claims |> Map.get("nonce") |> normalize_optional_string()
    actual_provider = claims |> Map.get("provider") |> normalize_optional_string()
    actual_provider_host = claims |> Map.get("provider_host") |> normalize_optional_string()

    cond do
      expected_nonce == nil or actual_nonce != expected_nonce ->
        {:error,
         typed_error(
           "broker_handoff_invalid_nonce",
           "Broker handoff nonce does not match the signed state.",
           "Restart provider sign-in and retry the handoff."
         )}

      expected_provider != nil and actual_provider != expected_provider ->
        {:error,
         typed_error(
           "broker_handoff_invalid_provider",
           "Broker handoff provider does not match the signed state.",
           "Restart provider sign-in and retry the handoff."
         )}

      expected_provider_host != nil and actual_provider_host != expected_provider_host ->
        {:error,
         typed_error(
           "broker_handoff_invalid_provider_host",
           "Broker handoff provider host does not match the signed state.",
           "Restart provider sign-in and retry the handoff."
         )}

      true ->
        :ok
    end
  end

  defp parse_expiry(exp) when is_integer(exp) do
    case DateTime.from_unix(exp) do
      {:ok, datetime} -> {:ok, datetime}
      _other -> invalid_expiry()
    end
  end

  defp parse_expiry(exp) when is_binary(exp) do
    case Integer.parse(exp) do
      {parsed, ""} -> parse_expiry(parsed)
      _other -> invalid_expiry()
    end
  end

  defp parse_expiry(_exp), do: invalid_expiry()

  defp invalid_expiry do
    {:error,
     typed_error(
       "broker_handoff_invalid_expiry",
       "Broker handoff expiry is invalid.",
       "Restart provider sign-in and retry the handoff."
     )}
  end

  defp ensure_not_expired(%DateTime{} = expires_at, %DateTime{} = now) do
    if DateTime.compare(expires_at, now) == :gt do
      :ok
    else
      {:error,
       typed_error(
         "broker_handoff_expired",
         "Broker handoff token has expired.",
         "Restart provider sign-in and retry the handoff."
       )}
    end
  end

  defp consume_nonce(nonce, expires_at) when is_binary(nonce) do
    case BrokerNonceStore.consume(nonce, expires_at) do
      :ok ->
        :ok

      {:error, :expired} ->
        {:error,
         typed_error(
           "broker_handoff_expired",
           "Broker handoff token has expired.",
           "Restart provider sign-in and retry the handoff."
         )}

      {:error, :replayed} ->
        {:error,
         typed_error(
           "broker_handoff_replayed",
           "Broker handoff nonce has already been used.",
           "Restart provider sign-in and retry the handoff."
         )}
    end
  end

  defp consume_nonce(_nonce, _expires_at) do
    {:error,
     typed_error(
       "broker_handoff_invalid_nonce",
       "Broker handoff nonce is invalid.",
       "Restart provider sign-in and retry the handoff."
     )}
  end

  defp normalize_audience(value) when is_binary(value), do: [value]

  defp normalize_audience(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_audience(_value), do: []

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp typed_error(error_type, message, recovery_instruction) do
    %{
      error_type: error_type,
      message: message,
      recovery_instruction: recovery_instruction
    }
  end
end
