defmodule JidoCodeWeb.ProviderAuthController do
  @moduledoc """
  Deployment-side contract endpoints for brokered provider auth.
  """

  # covers: auth.provider_broker_handoff.start_endpoint_contract
  # covers: auth.provider_broker_handoff.complete_endpoint_contract

  use JidoCodeWeb, :controller

  alias JidoCode.AuthProviders.{BrokerHandoff, BrokerState, ProviderConfig}

  def start(conn, %{"provider" => provider} = params) do
    provider_host = Map.get(params, "provider_host", default_provider_host(provider))
    redirect_path = Map.get(params, "redirect_path", "/")

    with {:ok, provider_config} <- fetch_provider_config(provider, provider_host),
         {:ok, issued_state} <-
           BrokerState.issue(%{
             provider: provider,
             provider_host: provider_host,
             broker_base_url: provider_config.broker_base_url,
             redirect_path: redirect_path
           }),
         {:ok, broker_url} <- build_broker_start_url(conn, provider, provider_host, provider_config, issued_state) do
      redirect(conn, external: broker_url)
    else
      {:error, %{error_type: "provider_login_not_configured"} = error} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: error})

      {:error, %{error_type: "broker_base_url_invalid"} = error} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: error})

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: error})
    end
  end

  def complete(conn, %{"provider" => provider, "state" => state_token, "handoff_token" => handoff_token}) do
    with {:ok, state_claims} <- BrokerState.verify(state_token),
         true <- state_claims.provider == provider,
         {:ok, provider_config} <- fetch_provider_config(provider, state_claims.provider_host),
         {:ok, validated} <- BrokerHandoff.validate(handoff_token, provider_config, state_claims) do
      json(conn, %{
        status: "broker_handoff_validated",
        provider: validated.provider,
        provider_host: validated.provider_host,
        nonce: validated.nonce,
        redirect_path: state_claims.redirect_path
      })
    else
      false ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: %{
            error_type: "broker_state_invalid_provider",
            message: "Provider path segment does not match the signed broker state.",
            recovery_instruction: "Restart provider sign-in and retry the handoff."
          }
        })

      {:error, %{error_type: "provider_login_not_configured"} = error} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: error})

      {:error, %{error_type: error_type} = error}
      when error_type in [
             "broker_handoff_invalid",
             "broker_handoff_invalid_issuer",
             "broker_handoff_invalid_audience",
             "broker_handoff_invalid_nonce",
             "broker_handoff_invalid_provider",
             "broker_handoff_invalid_provider_host",
             "broker_handoff_invalid_expiry",
             "broker_handoff_expired",
             "broker_handoff_replayed",
             "broker_jwks_unavailable"
           ] ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: error})

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: error})
    end
  end

  def complete(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{
        error_type: "broker_handoff_invalid",
        message: "Broker handoff parameters are invalid.",
        recovery_instruction: "Restart provider sign-in and retry the handoff."
      }
    })
  end

  defp fetch_provider_config(provider, provider_host) do
    normalized_provider = normalize_provider(provider)

    case ProviderConfig.get_by_provider_host(normalized_provider, provider_host, authorize?: false) do
      {:ok, %ProviderConfig{} = provider_config} ->
        {:ok, provider_config}

      {:ok, nil} ->
        provider_not_configured(normalized_provider, provider_host)

      {:error, _reason} ->
        provider_not_configured(normalized_provider, provider_host)
    end
  end

  defp provider_not_configured(provider, provider_host) do
    {:error,
     %{
       error_type: "provider_login_not_configured",
       message: "Provider login is not configured for this provider host.",
       recovery_instruction: "Create the provider login configuration before retrying this flow.",
       provider: provider,
       provider_host: provider_host
     }}
  end

  defp build_broker_start_url(conn, provider, provider_host, provider_config, issued_state) do
    broker_base_url =
      provider_config.broker_base_url
      |> normalize_optional_string()

    if broker_base_url == nil do
      {:error,
       %{
         error_type: "broker_base_url_invalid",
         message: "Broker base URL is not configured for this provider host.",
         recovery_instruction: "Update provider broker configuration and retry the start endpoint."
       }}
    else
      complete_url =
        url(
          conn,
          ~p"/auth/providers/#{provider}/complete?provider_host=#{provider_host}"
        )

      query =
        URI.encode_query(%{
          "state" => issued_state.token,
          "provider_host" => provider_host,
          "redirect_uri" => complete_url
        })

      {:ok, "#{String.trim_trailing(broker_base_url, "/")}/auth/providers/#{provider}/start?#{query}"}
    end
  end

  defp normalize_provider("github"), do: :github
  defp normalize_provider("gitlab"), do: :gitlab
  defp normalize_provider("bitbucket"), do: :bitbucket
  defp normalize_provider(provider) when is_atom(provider), do: provider

  defp default_provider_host("github"), do: "github.com"
  defp default_provider_host("gitlab"), do: "gitlab.com"
  defp default_provider_host("bitbucket"), do: "bitbucket.org"
  defp default_provider_host(_provider), do: "github.com"

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil
end
