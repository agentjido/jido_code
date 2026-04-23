defmodule JidoCodeWeb.BrowserSetup do
  @moduledoc false

  alias JidoCode.Repo
  alias JidoCodeWeb.ConnCase

  @checked_at ~U[2026-02-13 12:34:56Z]
  @owner_email "owner@example.com"
  @owner_password "owner-password-123"
  @scenario_modes ~w(normal fallback)

  def valid_scenario?(mode) when mode in @scenario_modes, do: true
  def valid_scenario?(_mode), do: false

  def owner_email, do: @owner_email
  def owner_password, do: @owner_password

  def apply_scenario!(mode) when mode in @scenario_modes do
    reset_browser_state!()
    configure_frontend_delivery!(mode)
    configure_project_importer!()
    seed_owner!()
    seed_system_config!()
    :ok
  end

  defp reset_browser_state! do
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])

    Application.delete_env(:jido_code, :setup_github_credential_checker)
    Application.delete_env(:jido_code, :setup_github_http_client)
    Application.delete_env(:jido_code, :setup_github_http_client_options)
    Application.delete_env(:jido_code, :setup_project_importer)
    Application.delete_env(:jido_code, :frontend_assets_override)

    System.delete_env("BURRITO_TARGET")
  end

  defp configure_frontend_delivery!("normal"), do: :ok

  defp configure_frontend_delivery!("fallback") do
    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })
  end

  defp configure_project_importer! do
    Application.put_env(:jido_code, :setup_project_importer, &browser_project_importer/1)
  end

  defp seed_owner! do
    ConnCase.register_owner(@owner_email, @owner_password)
  end

  defp seed_system_config! do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "System prerequisites verified (browser harness)."},
        "2" => %{
          "owner_email" => @owner_email,
          "owner_mode" => "created",
          "registration_actions_disabled" => true,
          "validated_note" => "Owner account bootstrapped."
        },
        "4" => %{
          "github_credentials" => %{
            "status" => "ready",
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => [
                  %{"id" => "repo_100", "full_name" => "owner/repo-one"},
                  %{"id" => "repo_200", "full_name" => "owner/repo-two"}
                ]
              }
            ]
          }
        }
      },
      default_environment: :sprite,
      workspace_root: nil
    })
  end

  defp browser_project_importer(%{selected_repository: selected_repository})
       when is_binary(selected_repository) do
    repo_name = selected_repository |> String.split("/") |> List.last()
    managed_repo_id = "managed-repo-#{repo_name}"

    %{
      checked_at: @checked_at,
      status: :ready,
      selected_repository: selected_repository,
      project_record: %{
        id: managed_repo_id,
        name: repo_name,
        source_kind: :github,
        source_identifier: selected_repository,
        github_full_name: selected_repository,
        local_path: nil,
        default_branch: "main",
        import_mode: :created,
        imported_at: @checked_at,
        clone_status: :ready,
        clone_status_history: [
          %{status: :pending},
          %{status: :cloning},
          %{status: :ready}
        ],
        last_synced_at: @checked_at
      },
      baseline_metadata: %{
        workspace_initialized: true,
        baseline_synced: true,
        default_workflow_registered: true,
        agent_configuration_registered: true,
        status: :ready,
        initialized_at: @checked_at,
        synced_branch: "main",
        last_synced_at: @checked_at,
        workspace_environment: :sprite,
        workspace_path: nil
      },
      detail: "Imported #{selected_repository} into the managed-repository control plane.",
      remediation: "Import complete.",
      error_type: nil
    }
  end
end
