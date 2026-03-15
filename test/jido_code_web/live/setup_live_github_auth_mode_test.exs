defmodule JidoCodeWeb.SetupLiveGitHubAuthModeTest do
  # covers: auth.github_integration.readiness_feedback
  # covers: auth.github_integration.non_blocking_local_auth
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias JidoCodeWeb.SetupLive

  @checked_at ~U[2026-02-13 12:34:56Z]

  setup_all do
    case Process.whereis(JidoCodeWeb.Endpoint) do
      nil -> start_supervised!(JidoCodeWeb.Endpoint)
      _pid -> :ok
    end

    :ok
  end

  test "render/1 shows PAT fallback mode with reduced-granularity feedback when GitHub App is not configured" do
    html =
      render_component(
        &SetupLive.render/1,
        setup_live_assigns(pat_fallback_ready_report())
      )

    assert html =~ ~s(id="setup-github-auth-mode")
    assert html =~ "PAT fallback"
    assert html =~ "reduced granularity relative to GitHub App mode"
    assert html =~ ~s(id="setup-github-readiness-status")
    assert html =~ "Ready"
  end

  test "render/1 keeps mode not ready when PAT validation fails and GitHub App is not configured" do
    html =
      render_component(
        &SetupLive.render/1,
        setup_live_assigns(pat_fallback_invalid_report())
      )

    assert html =~ ~s(id="setup-github-auth-mode")
    assert html =~ "Not ready"
    refute html =~ ~s(id="setup-github-auth-mode-feedback")
    assert html =~ ~s(id="setup-github-readiness-status")
    assert html =~ "Blocked"
    assert html =~ "github_pat_credentials_invalid"
  end

  defp setup_live_assigns(github_report) do
    %{
      flash: %{},
      onboarding_step: 4,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil,
      prerequisite_report: nil,
      provider_credential_report: nil,
      github_credential_report: github_report,
      webhook_simulation_report: nil,
      environment_defaults_report: nil,
      project_import_report: nil,
      available_repositories: [],
      owner_bootstrap: %{mode: :inactive, owner_email: nil, error: nil},
      save_error: nil,
      redirect_reason: "onboarding_incomplete",
      diagnostic: "Setup is required before protected routes are available.",
      step_form: default_step_form(),
      owner_form: default_owner_form(),
      owner_recovery_form: default_owner_recovery_form()
    }
  end

  defp default_step_form do
    to_form(
      %{
        "validated_note" => "",
        "execution_mode" => "cloud",
        "workspace_root" => "",
        "repository_full_name" => ""
      },
      as: :step
    )
  end

  defp default_owner_form do
    to_form(
      %{
        "email" => "",
        "password" => "",
        "password_confirmation" => ""
      },
      as: :owner
    )
  end

  defp default_owner_recovery_form do
    to_form(
      %{
        "email" => "",
        "password" => "",
        "password_confirmation" => "",
        "verification_phrase" => "",
        "verification_ack" => false
      },
      as: :owner_recovery
    )
  end

  defp pat_fallback_ready_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :not_configured,
          previous_status: :not_configured,
          transition: "Not configured -> Not configured",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail:
            "GitHub App credentials are not fully configured (`GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` are required).",
          remediation: "Set `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY`, then retry validation.",
          error_type: "github_app_not_configured",
          validated_at: nil,
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :ready,
          previous_status: :not_configured,
          transition: "Not configured -> Ready",
          owner_context: "owner@example.com",
          repository_access: :confirmed,
          repositories: ["owner/repo-one"],
          detail: "GitHub PAT fallback confirms repository access.",
          remediation: "Credential path is ready.",
          error_type: nil,
          validated_at: @checked_at,
          checked_at: @checked_at
        }
      ]
    }
  end

  defp pat_fallback_invalid_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :not_configured,
          previous_status: :not_configured,
          transition: "Not configured -> Not configured",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail:
            "GitHub App credentials are not fully configured (`GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` are required).",
          remediation: "Set `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY`, then retry validation.",
          error_type: "github_app_not_configured",
          validated_at: nil,
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "Configured GitHub PAT failed validation.",
          remediation: "Set a valid `GITHUB_PAT` and retry validation.",
          error_type: "github_pat_credentials_invalid",
          validated_at: nil,
          checked_at: @checked_at
        }
      ]
    }
  end
end
