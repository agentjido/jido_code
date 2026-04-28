defmodule JidoCodeWeb.PhaseSixtyIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: baseline.surface.public_entry_routes
  # covers: baseline.surface.welcome_landing_copy
  # covers: auth.system.ready_state_local_auth_handoff
  # covers: auth.provider_login_flow.redirect_path_completion
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  # covers: auth.self_hosted_provider_integration.login_and_service_ready
  # covers: setup.onboarding.admin_bootstrap_completion_gate
  # covers: setup.onboarding.post_bootstrap_start_surface
  # covers: setup.onboarding.explicit_completion_path_to_dashboard
  # covers: users.admin_system.bootstrap_admin
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AuthProviders.{BrokerNonceStore, BrokerState, ProviderConfig}
  alias JidoCode.Repo

  @checker_env :setup_github_credential_checker
  @resolver_env :provider_auth_broker_jwks_resolver
  @checked_at ~U[2026-04-25 13:45:00Z]

  setup do
    BrokerNonceStore.reset!()

    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_checker = Application.get_env(:jido_code, @checker_env, :__missing__)
    original_resolver = Application.get_env(:jido_code, @resolver_env, :__missing__)

    on_exit(fn ->
      restore_env(:system_config, original_config)
      restore_env(:system_config_loader, original_loader)
      restore_env(@checker_env, original_checker)
      restore_env(@resolver_env, original_resolver)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, @checker_env)

    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    })

    :ok
  end

  test "60.3.1 first-run bootstrap enters setup and completes into dashboard", %{conn: conn} do
    {:ok, welcome_view, _html} = live(conn, ~p"/welcome", on_error: :warn)

    welcome_view
    |> form("#welcome-owner-form", %{
      "owner" => %{
        "email" => "phase60-bootstrap-owner@example.com",
        "password" => "owner-password-123",
        "password_confirmation" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      welcome_view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/setup"

    assert_live_redirect(live(recycle(auth_response), ~p"/welcome", on_error: :warn), "/setup")

    {:ok, setup_view, _html} = live(recycle(auth_response), ~p"/setup", on_error: :warn)

    assert has_element?(setup_view, "#setup-complete-continue", "Continue to dashboard")

    setup_view
    |> element("#setup-complete-continue")
    |> render_click()

    assert_redirect(setup_view, "/dashboard?onboarding=completed")

    assert %{
             onboarding_completed: true,
             onboarding_step: 4,
             onboarding_state: %{
               "2" => %{"owner_email" => "phase60-bootstrap-owner@example.com"},
               "3" => %{"completion_note" => completion_note}
             }
           } = Application.get_env(:jido_code, :system_config)

    assert completion_note =~ "Setup completed."

    {:ok, dashboard_view, _html} =
      live(recycle(auth_response), ~p"/dashboard?onboarding=completed", on_error: :warn)

    assert has_element?(dashboard_view, "#dashboard-entry-summary", "authenticated product home")
  end

  test "60.3.2 ready-state local and provider sign-in land on dashboard while settings owns auth and integrations",
       %{conn: conn} do
    register_owner("phase60-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, ready_config())
    Application.put_env(:jido_code, @checker_env, fn _context -> ready_github_report() end)

    enable_provider_login!(:github, "github.com")

    {:ok, sign_in_view, _html} = live(conn, ~p"/sign-in", on_error: :warn)

    sign_in_view
    |> form("form[action='/auth/user/password/sign_in']", %{
      "user" => %{
        "email" => "phase60-owner@example.com",
        "password" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      sign_in_view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/dashboard"

    {:ok, welcome_view, _html} = live(recycle(auth_response), ~p"/welcome", on_error: :warn)

    assert has_element?(welcome_view, "#welcome-open-dashboard", "Open Dashboard")

    assert has_element?(
             welcome_view,
             ~s|a[href="/settings/auth"]#welcome-open-settings|,
             "Open Auth & Integrations"
           )

    refute has_element?(welcome_view, "#provider-login-settings")

    {:ok, dashboard_view, _html} = live(recycle(auth_response), ~p"/dashboard", on_error: :warn)

    assert has_element?(dashboard_view, "#dashboard-entry-summary", "authenticated product home")
    assert has_element?(dashboard_view, ~s|a[href="/settings/auth"]|, "Settings")

    {:ok, settings_view, _html} = live(recycle(auth_response), ~p"/settings/auth", on_error: :warn)

    assert has_element?(settings_view, "#settings-auth-provider-login-settings", "Provider Login")

    assert has_element?(
             settings_view,
             "#settings-auth-git-provider-integrations",
             "Git Provider Integrations"
           )

    assert has_element?(settings_view, "#settings-auth-github-service-status", "GitHub automation is ready.")

    start_response = get(build_conn(), ~p"/auth/providers/github/start?provider_host=github.com")
    redirected = redirected_to(start_response, 302)
    state_token = redirected |> broker_state_from_redirect() |> Map.fetch!("state")

    assert {:ok, claims} = BrokerState.verify(state_token)
    assert claims.redirect_path == "/dashboard"

    {issued_state, handoff_token} =
      valid_broker_handoff("phase60-ready-owner", %{
        "provider_email" => "phase60-owner@example.com",
        "provider_login" => "phase60-owner"
      })

    provider_response =
      get(
        build_conn(),
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )

    assert redirected_to(provider_response, 302) == "/dashboard"

    {:ok, provider_dashboard_view, provider_dashboard_html} =
      live(recycle(provider_response), ~p"/dashboard", on_error: :warn)

    assert has_element?(
             provider_dashboard_view,
             "#dashboard-entry-summary",
             "authenticated product home"
           )

    assert provider_dashboard_html =~ "phase60-owner@example.com"

    {:ok, provider_settings_view, _html} =
      live(recycle(provider_response), ~p"/settings/auth", on_error: :warn)

    assert has_element?(provider_settings_view, "#settings-auth-github-service-status", "GitHub automation is ready.")
    assert has_element?(provider_settings_view, "#settings-auth-provider-login-card-github", "Ready")
  end

  test "60.3.3 phase 60 plan, route specs, and contributor docs remain aligned" do
    phase_plan =
      repo_file!(".spec/planning/phase-60-welcome-dashboard-and-settings-convergence.md")

    baseline_spec = repo_file!(".spec/specs/baseline_surface.spec.md")
    auth_spec = repo_file!(".spec/specs/authentication_system.spec.md")
    provider_spec = repo_file!(".spec/specs/provider_login_flow.spec.md")
    operator_spec = repo_file!(".spec/specs/operator_auth_settings.spec.md")
    self_hosted_spec = repo_file!(".spec/specs/self_hosted_provider_integration.spec.md")
    setup_spec = repo_file!(".spec/specs/setup_onboarding.spec.md")
    user_spec = repo_file!(".spec/specs/user_administration.spec.md")
    package_spec = repo_file!(".spec/specs/package.spec.md")
    adr = repo_file!(".spec/decisions/jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff.md")
    readme = repo_file!("README.md")
    contributing = repo_file!("CONTRIBUTING.md")

    assert phase_plan =~ "[x] 60 Phase 60 - Welcome Dashboard And Settings Convergence"
    assert phase_plan =~ "[x] 60.1 Section - Final Authenticated Entry Convergence"
    assert phase_plan =~ "[x] 60.2 Section - Current-Truth, Docs, And Contributor Convergence"
    assert phase_plan =~ "[x] 60.3 Section - Phase Integration Tests"

    assert baseline_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"
    assert auth_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"
    assert provider_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"
    assert operator_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"
    assert self_hosted_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"
    assert setup_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"
    assert user_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"
    assert package_spec =~ "test/jido_code_web/live/phase_sixty_integration_test.exs"

    assert adr =~ "This decision is now landed in product code."

    assert readme =~ "## Route Orientation"
    assert readme =~ "/dashboard` is the durable ready-state authenticated landing"
    assert readme =~ "/settings/auth` is the durable home"

    assert contributing =~ "## Route Orientation"
    assert contributing =~ "/dashboard` is the durable ready-state authenticated landing"
    assert contributing =~ "/settings/auth` is the durable home"
  end

  defp ready_config do
    %{
      onboarding_completed: true,
      onboarding_step: 8,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    }
  end

  defp ready_github_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      owner_context: "phase60-owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :ready,
          detail: "GitHub App credentials are ready.",
          remediation: "GitHub App path is ready.",
          repository_access: :confirmed,
          repositories: ["agentjido/jido_code"],
          validated_at: @checked_at,
          checked_at: @checked_at
        }
      ]
    }
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

  defp current_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp handoff_token(jwk, overrides) do
    claims =
      Map.merge(
        %{
          "iss" => "https://broker.example.com",
          "aud" => "jido-code",
          "nonce" => "phase60-ready-owner",
          "provider" => "github",
          "provider_host" => "github.com",
          "provider_subject" => "12345",
          "provider_login" => "octocat",
          "provider_email" => "octocat@example.com",
          "email_verified" => true,
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

  defp broker_state_from_redirect(redirected) do
    redirected
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end

  defp assert_live_redirect({:error, {:redirect, %{to: path}}}, expected) when path == expected,
    do: :ok

  defp assert_live_redirect({:error, {:live_redirect, %{to: path}}}, expected)
       when path == expected,
       do: :ok

  defp assert_live_redirect(other, expected) do
    ExUnit.Assertions.flunk("expected live redirect to #{expected}, got: #{inspect(other)}")
  end

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
