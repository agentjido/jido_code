defmodule JidoCodeWeb.HomeLiveOperatorSettingsTest do
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.broker_trust_configuration_ui
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.integration_boundary_visible
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.AuthProviders.ProviderConfig

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

  test "authenticated landing page separates provider login from git provider integrations", %{
    conn: _conn
  } do
    Application.put_env(:jido_code, @checker_env, fn _context ->
      blocked_github_report()
    end)

    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token, _owner} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(view, "#provider-login-settings", "Provider Login")
    assert has_element?(view, "#git-provider-integrations", "Git Provider Integrations")
    assert has_element?(view, "#provider-login-card-github", "GitHub")
    assert has_element?(view, "#provider-login-card-gitlab", "GitLab")
    assert has_element?(view, "#provider-login-card-bitbucket", "Bitbucket")
    assert has_element?(view, "#github-service-status", "GitHub automation is blocked.")
    assert has_element?(view, "#git-provider-integrations", "vcs/github/app_id")
    assert has_element?(view, "#git-provider-integrations", "vcs/github/pat")
    assert has_element?(view, "#git-provider-integrations", "named placeholder adapter")
  end

  test "authenticated operator can persist broker trust and allowlist settings for GitHub", %{
    conn: _conn
  } do
    Application.put_env(:jido_code, @checker_env, fn _context ->
      ready_github_report()
    end)

    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token, _owner} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/welcome")

    view
    |> form("#provider-login-form-github", %{
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

    assert has_element?(view, "#provider-login-card-github", "Ready")

    {:ok, config} =
      ProviderConfig.get_by_provider_host(:github, "github.com", authorize?: false)

    assert config.enabled == true
    assert config.login_enabled == true
    assert config.allowlist_mode == :organizations
    assert config.allowlist_values == ["agentjido", "jido-labs"]
    assert config.broker_base_url == "https://broker.example.com"
    assert config.broker_issuer == "https://broker.example.com"
    assert config.broker_audience == "jido-code"
  end

  test "operator can refresh GitHub integration validation feedback", %{conn: _conn} do
    Application.put_env(:jido_code, @checker_env, fn _context ->
      blocked_github_report()
    end)

    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token, _owner} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(
             view,
             "#github-service-path-github_app",
             "GitHub App credentials are not fully configured."
           )

    Application.put_env(:jido_code, @checker_env, fn _context ->
      ready_github_report()
    end)

    view
    |> element("#refresh-github-service-checks")
    |> render_click()

    assert has_element?(view, "#github-service-status", "GitHub automation is ready.")
    assert has_element?(view, "#github-service-path-github_app", "GitHub App credentials are ready.")
    assert has_element?(view, "#github-service-path-pat", "PAT fallback confirms repository access.")
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
end
