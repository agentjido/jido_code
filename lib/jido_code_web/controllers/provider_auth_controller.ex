defmodule JidoCodeWeb.ProviderAuthController do
  @moduledoc """
  Deployment-side contract endpoints for brokered provider auth.
  """

  # covers: auth.provider_broker_handoff.start_endpoint_contract
  # covers: auth.provider_broker_handoff.complete_endpoint_contract
  # covers: auth.provider_broker_handoff.bootstrap_gate_before_handoff
  # covers: auth.provider_login_flow.broker_handoff_consumption
  # covers: auth.provider_login_flow.local_session_issuance
  # covers: auth.provider_login_flow.redirect_path_completion
  # covers: auth.self_hosted_provider_integration.login_and_service_ready
  # covers: auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
  # covers: auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
  # covers: auth.self_hosted_provider_integration.bootstrap_precedes_provider_login

  use JidoCodeWeb, :controller

  alias JidoCode.AuthProviders.{BrokerHandoff, BrokerState, ProviderConfig, ProviderConfigStore, ProviderLogin}
  alias JidoCode.Setup.BootstrapStatus

  def start(conn, %{"provider" => provider} = params) do
    provider_host = Map.get(params, "provider_host", default_provider_host(provider))
    redirect_path = normalize_redirect_path(Map.get(params, "redirect_path"))

    with :ok <- ensure_provider_login_available(),
         {:ok, provider_config} <- fetch_provider_config(provider, provider_host),
         :ok <- ensure_login_enabled(provider_config),
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

      {:error, %{error_type: "provider_login_disabled"} = error} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: error})

      {:error, %{error_type: "provider_login_bootstrap_required"} = error} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: error})

      {:error, %{error_type: "provider_login_invalid_bootstrap_state"} = error} ->
        conn
        |> put_status(:conflict)
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
    with :ok <- ensure_provider_login_available(),
         {:ok, state_claims} <- BrokerState.verify(state_token),
         true <- state_claims.provider == provider,
         {:ok, provider_config} <- fetch_provider_config(provider, state_claims.provider_host),
         :ok <- ensure_login_enabled(provider_config),
         {:ok, validated} <- BrokerHandoff.validate(handoff_token, provider_config, state_claims),
         {:ok, sign_in_result} <- ProviderLogin.sign_in(validated.claims) do
      conn
      |> delete_session(:return_to)
      |> configure_session(renew: true)
      |> put_session("product_user_token", sign_in_result.token)
      |> put_session("product_user_email", to_string(sign_in_result.session_user.email))
      |> assign(:current_user, sign_in_result.session_user)
      |> put_flash(:info, sign_in_message(sign_in_result, validated.provider))
      |> redirect(to: state_claims.redirect_path)
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

      {:error, %{error_type: "provider_login_disabled"} = error} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: error})

      {:error, %{error_type: "provider_login_bootstrap_required"} = error} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: error})

      {:error, %{error_type: "provider_login_invalid_bootstrap_state"} = error} ->
        conn
        |> put_status(:conflict)
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

      {:error, %{error_type: error_type} = error}
      when error_type in [
             "provider_identity_not_allowlisted",
             "provider_email_required_for_auto_create",
             "provider_sign_in_invalid_input",
             "provider_session_token_generation_failed"
           ] ->
        conn
        |> put_status(:unprocessable_entity)
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

  defp ensure_provider_login_available do
    case BootstrapStatus.current() do
      %{state: :bootstrap_required} ->
        {:error,
         %{
           error_type: "provider_login_bootstrap_required",
           message: "Create the first local admin account before using provider login.",
           recovery_instruction: "Open /welcome and complete first-run bootstrap."
         }}

      %{state: :invalid_state, diagnostic: diagnostic} ->
        {:error,
         %{
           error_type: "provider_login_invalid_bootstrap_state",
           message: diagnostic || "Provider login is unavailable until bootstrap state is repaired.",
           recovery_instruction: "Repair the local bootstrap state before retrying provider login."
         }}

      _other ->
        :ok
    end
  end

  defp fetch_provider_config(provider, provider_host) do
    normalized_provider = normalize_provider(provider)

    case ProviderConfigStore.get_by_provider_host(normalized_provider, provider_host) do
      {:ok, %ProviderConfig{} = provider_config} ->
        {:ok, provider_config}

      {:ok, nil} ->
        provider_not_configured(normalized_provider, provider_host)

      {:error, _reason} ->
        provider_not_configured(normalized_provider, provider_host)
    end
  end

  defp ensure_login_enabled(%ProviderConfig{enabled: true, login_enabled: true}), do: :ok

  defp ensure_login_enabled(%ProviderConfig{} = provider_config) do
    {:error,
     %{
       error_type: "provider_login_disabled",
       message: "Provider login is disabled for this provider host.",
       recovery_instruction: "Enable provider login before starting or completing this flow.",
       provider: provider_config.provider,
       provider_host: provider_config.provider_host
     }}
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

  defp sign_in_message(sign_in_result, provider) do
    provider_name = provider_display_name(provider)

    case sign_in_result.resolution do
      :existing_identity -> "You are now signed in with #{provider_name}."
      :linked_by_email -> "Your #{provider_name} identity is now linked and signed in."
      :created_user -> "Your local account was created and signed in with #{provider_name}."
    end
  end

  defp normalize_redirect_path(value) when is_binary(value) do
    case String.trim(value) do
      "" -> default_redirect_path()
      <<"/", _::binary>> = path -> path
      _other -> default_redirect_path()
    end
  end

  defp normalize_redirect_path(_value), do: default_redirect_path()

  defp default_redirect_path do
    case BootstrapStatus.current().state do
      :continue_setup -> "/setup"
      :ready -> "/dashboard"
      _other -> "/welcome"
    end
  end

  defp provider_display_name("github"), do: "GitHub"
  defp provider_display_name("gitlab"), do: "GitLab"
  defp provider_display_name("bitbucket"), do: "Bitbucket"

  defp provider_display_name(provider) when is_atom(provider),
    do: provider |> Atom.to_string() |> provider_display_name()

  defp provider_display_name(provider), do: provider |> to_string() |> String.capitalize()

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil
end
