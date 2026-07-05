defmodule JidoCodeWeb.SelfHostedProviderAuthTest do
  # covers: auth.self_hosted_provider_integration.login_and_service_ready
  # covers: auth.self_hosted_provider_integration.service_independent_of_login_toggle
  # covers: auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
  # covers: auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
  # covers: auth.self_hosted_provider_integration.bootstrap_precedes_provider_login
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AuthProviders.{BrokerNonceStore, BrokerState, ProviderConfigStore}
  alias JidoCode.Setup.OwnerStore

  @resolver_env :provider_auth_broker_jwks_resolver
  @managed_app_env_keys [
    :setup_github_credential_checker,
    :github_app_id,
    :github_app_private_key,
    :github_app_installation_token,
    :github_app_accessible_repos,
    :github_app_expected_repos,
    :github_pat,
    :github_pat_accessible_repos
  ]

  setup do
    BrokerNonceStore.reset!()

    original_resolver = Application.get_env(:jido_code, @resolver_env, :__missing__)

    original_app_env =
      Map.new(@managed_app_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    on_exit(fn ->
      case original_resolver do
        :__missing__ -> Application.delete_env(:jido_code, @resolver_env)
        value -> Application.put_env(:jido_code, @resolver_env, value)
      end

      Enum.each(original_app_env, fn {key, value} ->
        case value do
          :__missing__ -> Application.delete_env(:jido_code, key)
          restored -> Application.put_env(:jido_code, key, restored)
        end
      end)
    end)

    assert {:ok, _count} = OwnerStore.delete_all_users()

    :ok
  end

  test "self-hosted deployment supports provider login and GitHub service auth together", %{
    conn: conn
  } do
    bootstrap_owner("owner@example.com", "owner-password-123")
    configure_github_service_ready!()
    enable_provider_login!(:github, "github.com")
    {issued_state, handoff_token} = valid_broker_handoff("integration-enabled")

    response_conn =
      get(
        conn,
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )

    assert redirected_to(response_conn, 302) == "/dashboard"

    {:ok, dashboard_view, _html} = live(recycle(response_conn), ~p"/dashboard")

    assert render(dashboard_view) =~ "octocat@example.com"
    assert has_element?(dashboard_view, "#dashboard-entry-summary", "authenticated product home")

    {:ok, settings_view, _html} = live(recycle(response_conn), ~p"/settings/auth")

    assert has_element?(settings_view, "#settings-auth-provider-login-card-github", "Ready")
    assert has_element?(settings_view, "#settings-auth-github-service-status", "GitHub automation is ready.")
    assert has_element?(settings_view, "#settings-auth-github-service-path-github_app", "Ready")
  end

  test "GitHub service auth remains available when provider login is disabled", %{conn: conn} do
    bootstrap_owner("owner@example.com", "owner-password-123")
    configure_github_service_ready!()
    enable_provider_login!(:github, "github.com", enabled: false, login_enabled: false)
    {issued_state, handoff_token} = valid_broker_handoff("integration-disabled")

    response =
      conn
      |> get(
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )
      |> json_response(403)

    assert response["error"]["error_type"] == "provider_login_disabled"

    {authed_conn, _session_token, _owner} =
      authenticate_bootstrap_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/auth")

    assert has_element?(view, "#settings-auth-provider-login-card-github", "Disabled")
    assert has_element?(view, "#settings-auth-github-service-status", "GitHub automation is ready.")
  end

  test "broker unavailability keeps local email auth as the fallback path", %{conn: conn} do
    bootstrap_owner("owner@example.com", "owner-password-123")
    enable_provider_login!(:github, "github.com")
    {:ok, issued_state} = issue_state("broker-unavailable")

    Application.put_env(:jido_code, @resolver_env, fn _config ->
      {:error, :jwks_unavailable}
    end)

    response =
      conn
      |> get(
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=unavailable-token"
      )
      |> json_response(401)

    assert response["error"]["error_type"] == "broker_jwks_unavailable"

    {:ok, anonymous_view, _html} = live(build_conn(), ~p"/welcome")

    assert has_element?(anonymous_view, "a", "Sign In")
    refute has_element?(anonymous_view, "a", "Create Account")

    assert has_element?(
             anonymous_view,
             ~s|a[href="/auth/providers/github/start?provider_host=github.com"]|,
             "Sign In with GitHub"
           )

    bootstrap_owner("fallback@example.com", "fallback-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_bootstrap_owner_conn("fallback@example.com", "fallback-password-123")

    {:ok, authed_view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert render(authed_view) =~ "fallback@example.com"
    assert has_element?(authed_view, "a[href=\"/sign-out\"]", "Sign Out")
  end

  test "allowlist rejection blocks provider login without breaking GitHub service readiness", %{
    conn: conn
  } do
    bootstrap_owner("owner@example.com", "owner-password-123")
    configure_github_service_ready!()

    enable_provider_login!(:github, "github.com",
      allowlist_mode: :organizations,
      allowlist_values: ["agentjido"]
    )

    {issued_state, handoff_token} =
      valid_broker_handoff("allowlist-rejection", %{
        "provider_email" => "blocked@example.com",
        "organizations" => ["different-org"]
      })

    response_conn =
      get(
        conn,
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )

    response = json_response(response_conn, 422)

    assert response["error"]["error_type"] == "provider_identity_not_allowlisted"
    assert get_session(response_conn, "product_user_token") == nil

    {authed_conn, _session_token, _owner} =
      authenticate_bootstrap_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/auth")

    assert has_element?(view, "#settings-auth-provider-login-card-github", "Ready")
    assert has_element?(view, "#settings-auth-github-service-status", "GitHub automation is ready.")
  end

  defp configure_github_service_ready! do
    Application.delete_env(:jido_code, :setup_github_credential_checker)
    Application.put_env(:jido_code, :github_app_id, "1234")
    Application.put_env(:jido_code, :github_app_private_key, "test-private-key")
    Application.put_env(:jido_code, :github_app_installation_token, "installation-token")
    Application.put_env(:jido_code, :github_app_accessible_repos, ["agentjido/jido_code"])
    Application.delete_env(:jido_code, :github_app_expected_repos)
    Application.delete_env(:jido_code, :github_pat)
    Application.delete_env(:jido_code, :github_pat_accessible_repos)
  end

  defp issue_state(nonce, redirect_path \\ "/dashboard") do
    BrokerState.issue(
      %{
        provider: "github",
        provider_host: "github.com",
        broker_base_url: "https://broker.example.com",
        redirect_path: redirect_path
      },
      now: current_now(),
      nonce: nonce
    )
  end

  defp valid_broker_handoff(nonce, claim_overrides \\ %{}) do
    {:ok, issued_state} = issue_state(nonce)

    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})

    Application.put_env(:jido_code, @resolver_env, fn _config ->
      {:ok, %{"keys" => [public_jwk_map(jwk)]}}
    end)

    handoff_token =
      handoff_token(
        jwk,
        %{
          "nonce" => nonce,
          "exp" => DateTime.to_unix(DateTime.add(DateTime.utc_now(), 300, :second))
        }
        |> Map.merge(claim_overrides)
      )

    {issued_state, handoff_token}
  end

  defp enable_provider_login!(provider, provider_host, overrides \\ []) do
    attrs =
      %{
        provider: provider,
        provider_host: provider_host,
        enabled: true,
        login_enabled: true,
        allowlist_mode: :none,
        allowlist_values: [],
        broker_issuer: "https://broker.example.com",
        broker_audience: "jido-code",
        broker_base_url: "https://broker.example.com"
      }
      |> Map.merge(Map.new(overrides))

    {:ok, config} = ProviderConfigStore.upsert(attrs)
    config
  end

  defp bootstrap_owner(email, password) do
    JidoCodeWeb.ConnCase.register_owner(email, password)
    seed_product_owner!(email)
  end

  defp seed_product_owner!(email) do
    case OwnerStore.get_by_email(email) do
      {:ok, nil} ->
        {:ok, _owner} = OwnerStore.create_owner(%{email: email})

      {:ok, _owner} ->
        :ok
    end

    :ok
  end

  defp authenticate_bootstrap_owner_conn(email, password) do
    {auth_response, session_token, owner} =
      JidoCodeWeb.ConnCase.authenticate_owner_conn(email, password, return_owner: true)

    assert is_binary(session_token)
    {recycle(auth_response), session_token, owner}
  end

  defp handoff_token(jwk, overrides) do
    claims =
      Map.merge(
        %{
          "iss" => "https://broker.example.com",
          "aud" => "jido-code",
          "nonce" => "integration-nonce",
          "provider" => "github",
          "provider_host" => "github.com",
          "provider_subject" => "12345",
          "provider_login" => "octocat",
          "provider_email" => "octocat@example.com",
          "email_verified" => true,
          "organizations" => ["agentjido"],
          "exp" => DateTime.to_unix(DateTime.add(DateTime.utc_now(), 300, :second))
        },
        overrides
      )

    {_, compact} =
      jwk
      |> JOSE.JWT.sign(%{"alg" => "EdDSA"}, JOSE.JWT.from_map(claims))
      |> JOSE.JWS.compact()

    compact
  end

  defp public_jwk_map(jwk) do
    jwk
    |> JOSE.JWK.to_public_map()
    |> elem(1)
  end

  defp current_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
