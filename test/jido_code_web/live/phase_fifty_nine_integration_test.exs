defmodule JidoCodeWeb.PhaseFiftyNineIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.broker_trust_configuration_ui
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.integration_boundary_visible
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  # covers: baseline.surface.welcome_landing_copy
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AuthProviders.ProviderConfig

  @checker_env :setup_github_credential_checker
  @checked_at ~U[2026-03-15 18:30:00Z]

  setup do
    original_checker = Application.get_env(:jido_code, @checker_env, :__missing__)
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)

    on_exit(fn ->
      restore_env(@checker_env, original_checker)
      restore_env(:system_config, original_config)
      restore_env(:system_config_loader, original_loader)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.put_env(:jido_code, :system_config, ready_config())

    :ok
  end

  test "59.3.1 settings auth surface owns provider login and github validation while welcome stays a handoff",
       %{conn: conn} do
    Application.put_env(:jido_code, @checker_env, fn _context ->
      blocked_github_report()
    end)

    register_owner("phase59-owner@example.com", "owner-password-123")

    assert_live_redirect(live(conn, ~p"/settings/auth", on_error: :warn), "/welcome")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("phase59-owner@example.com", "owner-password-123", return_owner: true)

    {:ok, settings_view, _html} = live(recycle(authed_conn), ~p"/settings/auth")

    assert has_element?(settings_view, "#settings-auth-provider-login-settings", "Provider Login")

    assert has_element?(
             settings_view,
             "#settings-auth-git-provider-integrations",
             "Git Provider Integrations"
           )

    settings_view
    |> form("#settings-auth-provider-login-form-github", %{
      "provider_login" => %{
        "provider" => "github",
        "enabled" => "true",
        "login_enabled" => "true",
        "allowlist_mode" => "organizations",
        "allowlist_values" => "agentjido\njido-labs",
        "broker_base_url" => "https://broker.example.com",
        "broker_issuer" => "https://broker.example.com",
        "broker_audience" => "jido-code"
      }
    })
    |> render_submit()

    assert has_element?(settings_view, "#settings-auth-provider-login-card-github", "Ready")

    {:ok, config} =
      ProviderConfig.get_by_provider_host(:github, "github.com", authorize?: false)

    assert config.enabled == true
    assert config.login_enabled == true
    assert config.allowlist_mode == :organizations
    assert config.allowlist_values == ["agentjido", "jido-labs"]

    Application.put_env(:jido_code, @checker_env, fn _context ->
      ready_github_report()
    end)

    settings_view
    |> element("#settings-auth-refresh-github-service-checks")
    |> render_click()

    assert has_element?(settings_view, "#settings-auth-github-service-status", "GitHub automation is ready.")

    assert has_element?(
             settings_view,
             "#settings-auth-github-service-path-github_app",
             "GitHub App credentials are ready."
           )

    {:ok, welcome_view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(
             welcome_view,
             ~s|a[href="/settings/auth"]#welcome-open-settings|,
             "Open Auth & Integrations"
           )

    assert has_element?(welcome_view, "#welcome-ready-handoff-note", "Dashboard is the default authenticated entry")
    refute has_element?(welcome_view, "#welcome-operator-settings-handoff")
    refute has_element?(welcome_view, "#provider-login-settings")
    refute has_element?(welcome_view, "#git-provider-integrations")
  end

  test "59.3.2 phase 59 plan and current-truth specs remain aligned" do
    phase_plan =
      repo_file!(".spec/planning/phase-59-operator-auth-settings-settings-surface-adoption.md")

    operator_spec = repo_file!(".spec/specs/operator_auth_settings.spec.md")
    baseline_spec = repo_file!(".spec/specs/baseline_surface.spec.md")
    package_spec = repo_file!(".spec/specs/package.spec.md")
    auth_spec = repo_file!(".spec/specs/authentication_system.spec.md")

    assert phase_plan =~ "[x] 59 Phase 59 - Operator Auth Settings Settings-Surface Adoption"
    assert phase_plan =~ "[x] 59.1 Section - Settings Information Architecture And Route Ownership"
    assert phase_plan =~ "[x] 59.2 Section - Welcome-To-Settings Handoff And Surface Cleanup"
    assert phase_plan =~ "[x] 59.3 Section - Phase Integration Tests"

    assert operator_spec =~ "signed-in `/welcome` remains only a compact handoff into dashboard and settings"
    assert operator_spec =~ "test/jido_code_web/live/phase_fifty_nine_integration_test.exs"
    assert baseline_spec =~ "test/jido_code_web/live/phase_fifty_nine_integration_test.exs"
    assert package_spec =~ "test/jido_code_web/live/phase_fifty_nine_integration_test.exs"
    assert auth_spec =~ "compact dashboard/settings handoff"
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

  defp blocked_github_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      owner_context: "phase59-owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :not_configured,
          detail: "GitHub App credentials are not fully configured.",
          remediation: "Set GitHub App credentials and retry validation.",
          repository_access: :unconfirmed,
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :invalid,
          detail: "PAT fallback is unavailable until a deployment-local token is configured.",
          remediation: "Set a valid GitHub PAT or prefer a GitHub App installation token.",
          repository_access: :unconfirmed,
          checked_at: @checked_at
        }
      ]
    }
  end

  defp ready_github_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      owner_context: "phase59-owner@example.com",
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
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :ready,
          detail: "PAT fallback confirms repository access.",
          remediation: "PAT fallback is available.",
          repository_access: :confirmed,
          repositories: ["agentjido/jido_code"],
          validated_at: @checked_at,
          checked_at: @checked_at
        }
      ]
    }
  end

  defp assert_live_redirect({:error, {:redirect, %{to: path}}}, expected) when path == expected,
    do: :ok

  defp assert_live_redirect({:error, {:live_redirect, %{to: path}}}, expected)
       when path == expected,
       do: :ok

  defp assert_live_redirect(other, expected) do
    ExUnit.Assertions.flunk("expected live redirect to #{expected}, got: #{inspect(other)}")
  end

  defp repo_file!(relative_path) do
    relative_path
    |> Path.expand(File.cwd!())
    |> File.read!()
  end
end
