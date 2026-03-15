defmodule JidoCode.AuthProviders.BrokerState do
  @moduledoc """
  Signed deployment-side state for brokered provider login handoffs.
  """

  # covers: auth.provider_broker_handoff.state_token_signature
  # covers: auth.provider_broker_handoff.state_token_ttl
  # covers: auth.provider_broker_handoff.nonce_binding

  alias JidoCodeWeb.Endpoint

  @salt "provider_auth_broker_state"
  @default_ttl_seconds 300
  @providers ~w(github gitlab bitbucket)

  @type typed_error :: %{
          error_type: String.t(),
          message: String.t(),
          recovery_instruction: String.t()
        }

  @type state_claims :: %{
          provider: String.t(),
          provider_host: String.t(),
          broker_base_url: String.t(),
          redirect_path: String.t(),
          nonce: String.t(),
          issued_at: DateTime.t(),
          expires_at: DateTime.t()
        }

  @type issued_state :: %{
          token: String.t(),
          claims: state_claims()
        }

  @doc """
  Issues a signed state token for a provider-auth start request.
  """
  @spec issue(map(), keyword()) :: {:ok, issued_state()} | {:error, typed_error()}
  def issue(params, opts \\ [])

  def issue(params, opts) when is_map(params) and is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now() |> DateTime.truncate(:second))
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    nonce = Keyword.get(opts, :nonce, generate_nonce())

    with {:ok, provider} <- normalize_provider(Map.get(params, :provider) || Map.get(params, "provider")),
         {:ok, provider_host} <-
           normalize_required_string(
             Map.get(params, :provider_host) || Map.get(params, "provider_host"),
             "provider_host_invalid",
             "Provider host must be a non-empty string."
           ),
         {:ok, broker_base_url} <-
           normalize_required_string(
             Map.get(params, :broker_base_url) || Map.get(params, "broker_base_url"),
             "broker_base_url_invalid",
             "Broker base URL must be a non-empty string."
           ),
         {:ok, redirect_path} <-
           normalize_redirect_path(Map.get(params, :redirect_path) || Map.get(params, "redirect_path")),
         {:ok, expires_at} <- compute_expiry(now, ttl_seconds) do
      claims = %{
        provider: provider,
        provider_host: provider_host,
        broker_base_url: broker_base_url,
        redirect_path: redirect_path,
        nonce: nonce,
        issued_at: now,
        expires_at: expires_at
      }

      token =
        Phoenix.Token.sign(
          Keyword.get(opts, :endpoint, Endpoint),
          @salt,
          serialize_claims(claims)
        )

      {:ok, %{token: token, claims: claims}}
    end
  end

  def issue(_params, _opts) do
    {:error,
     typed_error(
       "broker_state_invalid",
       "Broker state parameters are invalid.",
       "Retry the provider-auth start request with a valid provider and callback context."
     )}
  end

  @doc """
  Verifies and decodes a signed broker state token.
  """
  @spec verify(String.t(), keyword()) :: {:ok, state_claims()} | {:error, typed_error()}
  def verify(token, opts \\ [])

  def verify(token, opts) when is_binary(token) and is_list(opts) do
    max_age = Keyword.get(opts, :max_age, @default_ttl_seconds)

    case Phoenix.Token.verify(Keyword.get(opts, :endpoint, Endpoint), @salt, token, max_age: max_age) do
      {:ok, claims} when is_map(claims) ->
        normalize_claims(claims, Keyword.get(opts, :now, DateTime.utc_now() |> DateTime.truncate(:second)))

      {:error, :expired} ->
        {:error,
         typed_error(
           "broker_state_expired",
           "Broker state has expired.",
           "Restart provider sign-in and retry the handoff."
         )}

      {:error, _reason} ->
        {:error,
         typed_error(
           "broker_state_invalid",
           "Broker state could not be verified.",
           "Restart provider sign-in and retry the handoff."
         )}
    end
  end

  def verify(_token, _opts) do
    {:error,
     typed_error(
       "broker_state_invalid",
       "Broker state could not be verified.",
       "Restart provider sign-in and retry the handoff."
     )}
  end

  defp normalize_claims(claims, now) when is_map(claims) do
    with {:ok, provider} <- normalize_provider(Map.get(claims, "provider") || Map.get(claims, :provider)),
         {:ok, provider_host} <-
           normalize_required_string(
             Map.get(claims, "provider_host") || Map.get(claims, :provider_host),
             "provider_host_invalid",
             "Provider host must be a non-empty string."
           ),
         {:ok, broker_base_url} <-
           normalize_required_string(
             Map.get(claims, "broker_base_url") || Map.get(claims, :broker_base_url),
             "broker_base_url_invalid",
             "Broker base URL must be a non-empty string."
           ),
         {:ok, redirect_path} <-
           normalize_redirect_path(Map.get(claims, "redirect_path") || Map.get(claims, :redirect_path)),
         {:ok, nonce} <-
           normalize_required_string(
             Map.get(claims, "nonce") || Map.get(claims, :nonce),
             "broker_state_invalid",
             "Broker nonce must be a non-empty string."
           ),
         {:ok, issued_at} <- parse_datetime(Map.get(claims, "issued_at") || Map.get(claims, :issued_at)),
         {:ok, expires_at} <- parse_datetime(Map.get(claims, "expires_at") || Map.get(claims, :expires_at)),
         :ok <- ensure_not_expired(expires_at, now) do
      {:ok,
       %{
         provider: provider,
         provider_host: provider_host,
         broker_base_url: broker_base_url,
         redirect_path: redirect_path,
         nonce: nonce,
         issued_at: issued_at,
         expires_at: expires_at
       }}
    end
  end

  defp normalize_claims(_claims, _now) do
    {:error,
     typed_error(
       "broker_state_invalid",
       "Broker state payload is invalid.",
       "Restart provider sign-in and retry the handoff."
     )}
  end

  defp compute_expiry(%DateTime{} = now, ttl_seconds)
       when is_integer(ttl_seconds) and ttl_seconds > 0 do
    {:ok, DateTime.add(now, ttl_seconds, :second)}
  end

  defp compute_expiry(_now, _ttl_seconds) do
    {:error,
     typed_error(
       "broker_state_invalid",
       "Broker state TTL is invalid.",
       "Retry the provider-auth start request with a valid TTL."
     )}
  end

  defp normalize_provider(provider) when provider in @providers, do: {:ok, provider}
  defp normalize_provider(provider) when is_atom(provider), do: normalize_provider(Atom.to_string(provider))

  defp normalize_provider(_provider) do
    {:error,
     typed_error(
       "provider_invalid",
       "Provider must be one of github, gitlab, or bitbucket.",
       "Retry the provider-auth request with a supported provider."
     )}
  end

  defp normalize_redirect_path(nil), do: {:ok, "/"}

  defp normalize_redirect_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    if trimmed == "" or not String.starts_with?(trimmed, "/") do
      {:ok, "/"}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_redirect_path(_path), do: {:ok, "/"}

  defp normalize_required_string(value, error_type, message) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, typed_error(error_type, message, "Update the provider configuration and retry.")}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_required_string(_value, error_type, message) do
    {:error, typed_error(error_type, message, "Update the provider configuration and retry.")}
  end

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      _other ->
        {:error,
         typed_error(
           "broker_state_invalid",
           "Broker state timestamps are invalid.",
           "Restart provider sign-in and retry the handoff."
         )}
    end
  end

  defp parse_datetime(_value) do
    {:error,
     typed_error(
       "broker_state_invalid",
       "Broker state timestamps are invalid.",
       "Restart provider sign-in and retry the handoff."
     )}
  end

  defp ensure_not_expired(%DateTime{} = expires_at, %DateTime{} = now) do
    if DateTime.compare(expires_at, now) == :gt do
      :ok
    else
      {:error,
       typed_error(
         "broker_state_expired",
         "Broker state has expired.",
         "Restart provider sign-in and retry the handoff."
       )}
    end
  end

  defp serialize_claims(claims) do
    %{
      "provider" => claims.provider,
      "provider_host" => claims.provider_host,
      "broker_base_url" => claims.broker_base_url,
      "redirect_path" => claims.redirect_path,
      "nonce" => claims.nonce,
      "issued_at" => DateTime.to_iso8601(claims.issued_at),
      "expires_at" => DateTime.to_iso8601(claims.expires_at)
    }
  end

  defp generate_nonce do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp typed_error(error_type, message, recovery_instruction) do
    %{
      error_type: error_type,
      message: message,
      recovery_instruction: recovery_instruction
    }
  end
end
