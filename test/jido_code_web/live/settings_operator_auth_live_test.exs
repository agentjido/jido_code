defmodule JidoCodeWeb.SettingsOperatorAuthLiveTest do
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.broker_trust_configuration_ui
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.integration_boundary_visible
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AuthProviders.ProviderConfigStore

  @checker_env :setup_github_credential_checker
  @checked_at ~U[2026-03-15 18:30:00Z]

  setup do
    original_checker = Application.get_env(:jido_code, @checker_env, :__missing__)

    on_exit(fn ->
      case original_checker do
        :__missing__ -> Application.delete_env(:jido_code, @checker_env)
        value -> Application.put_env(:jido_code, @checker_env, value)
      end
    end)

    :ok
  end

  test "authenticated operator can open the settings auth tab as a durable auth-and-integrations destination",
       %{conn: _conn} do
    Application.put_env(:jido_code, @checker_env, fn _context ->
      blocked_github_report()
    end)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123", return_owner: true)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/auth")

    assert has_element?(view, "#settings-nav-auth", "Auth & Integrations")
    assert has_element?(view, "#settings-auth-provider-login-settings", "Provider Login")
    assert has_element?(view, "#settings-auth-git-provider-integrations", "Git Provider Integrations")
    assert has_element?(view, "#settings-auth-provider-login-card-github", "GitHub")
    assert has_element?(view, "#settings-auth-provider-login-card-gitlab", "GitLab")
    assert has_element?(view, "#settings-auth-provider-login-card-bitbucket", "Bitbucket")
    assert has_element?(view, "#settings-auth-github-service-status", "GitHub automation is blocked.")
    assert has_element?(view, "#settings-auth-github-service-secret-refs", "vcs/github/app_id")
    assert has_element?(view, "#settings-auth-github-service-secret-refs", "vcs/github/pat")
    assert has_element?(view, "#settings-auth-git-provider-integrations", "named placeholder adapter")
  end

  test "authenticated operator can persist broker trust and allowlist settings from settings auth tab",
       %{conn: _conn} do
    Application.put_env(:jido_code, @checker_env, fn _context ->
      ready_github_report()
    end)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123", return_owner: true)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/auth")

    view
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

    assert has_element?(view, "#settings-auth-provider-login-card-github", "Ready")

    {:ok, config} =
      ProviderConfigStore.get_by_provider_host(:github, "github.com")

    assert config.enabled == true
    assert config.login_enabled == true
    assert config.allowlist_mode == :organizations
    assert config.allowlist_values == ["agentjido", "jido-labs"]
    assert config.broker_base_url == "https://broker.example.com"
    assert config.broker_issuer == "https://broker.example.com"
    assert config.broker_audience == "jido-code"
  end

  test "authenticated operator can refresh github integration validation feedback from settings auth tab",
       %{conn: _conn} do
    Application.put_env(:jido_code, @checker_env, fn _context ->
      blocked_github_report()
    end)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123", return_owner: true)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/auth")

    assert has_element?(
             view,
             "#settings-auth-github-service-path-github_app",
             "GitHub App credentials are not fully configured."
           )

    Application.put_env(:jido_code, @checker_env, fn _context ->
      ready_github_report()
    end)

    view
    |> element("#settings-auth-refresh-github-service-checks")
    |> render_click()

    assert has_element?(view, "#settings-auth-github-service-status", "GitHub automation is ready.")

    assert has_element?(
             view,
             "#settings-auth-github-service-path-github_app",
             "GitHub App credentials are ready."
           )

    assert has_element?(
             view,
             "#settings-auth-github-service-path-pat",
             "PAT fallback confirms repository access."
           )
  end

  defp blocked_github_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      owner_context: "owner@example.com",
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
      owner_context: "owner@example.com",
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
end
