defmodule JidoCodeWeb.SelfHostedProviderAuthTest do
  # covers: auth.self_hosted_provider_integration.login_and_service_ready
  # covers: auth.self_hosted_provider_integration.service_independent_of_login_toggle
  # covers: auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
  # covers: auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.AuthProviders.{BrokerNonceStore, BrokerState, ProviderConfig}

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

  @now ~U[2026-03-15 19:15:00Z]

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

    :ok
  end

  test "self-hosted deployment supports provider login and GitHub service auth together", %{
    conn: conn
  } do
    configure_github_service_ready!()
    enable_provider_login!(:github, "github.com")
    {issued_state, handoff_token} = valid_broker_handoff("integration-enabled")

    response_conn =
      get(
        conn,
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )

    assert redirected_to(response_conn, 302) == "/welcome"

    {:ok, view, _html} = live(recycle(response_conn), ~p"/welcome")

    assert render(view) =~ "octocat@example.com"
    assert has_element?(view, "#provider-login-card-github", "Ready")
    assert has_element?(view, "#github-service-status", "GitHub automation is ready.")
    assert has_element?(view, "#github-service-path-github_app", "Ready")
  end

  test "GitHub service auth remains available when provider login is disabled", %{conn: conn} do
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

    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token, _owner} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(view, "#provider-login-card-github", "Disabled")
    assert has_element?(view, "#github-service-status", "GitHub automation is ready.")
  end

  test "broker unavailability keeps local email auth as the fallback path", %{conn: conn} do
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
    assert has_element?(anonymous_view, "a", "Create Account")

    assert has_element?(
             anonymous_view,
             ~s|a[href="/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome"]|,
             "Sign In with GitHub"
           )

    register_owner("fallback@example.com", "fallback-password-123")
    {authed_conn, _session_token, _owner} = authenticate_owner_conn("fallback@example.com", "fallback-password-123")

    {:ok, authed_view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert render(authed_view) =~ "fallback@example.com"
    assert has_element?(authed_view, "a[href=\"/sign-out\"]", "Sign Out")
  end

  test "allowlist rejection blocks provider login without breaking GitHub service readiness", %{
    conn: conn
  } do
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
    assert get_session(response_conn, "user_token") == nil

    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token, _owner} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(view, "#provider-login-card-github", "Ready")
    assert has_element?(view, "#github-service-status", "GitHub automation is ready.")
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

  defp issue_state(nonce, redirect_path \\ "/welcome") do
    BrokerState.issue(
      %{
        provider: "github",
        provider_host: "github.com",
        broker_base_url: "https://broker.example.com",
        redirect_path: redirect_path
      },
      now: @now,
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

    {:ok, config} = ProviderConfig.upsert(attrs, authorize?: false)
    config
  end

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, _owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    :ok
  end

  defp authenticate_owner_conn(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response = build_conn() |> get(owner_sign_in_with_token_path(strategy, token))
    assert redirected_to(auth_response, 302) == "/"
    session_token = get_session(auth_response, "user_token")
    assert is_binary(session_token)
    {recycle(auth_response), session_token, owner}
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
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
end
