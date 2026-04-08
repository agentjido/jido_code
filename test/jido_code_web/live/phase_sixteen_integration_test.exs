defmodule JidoCodeWeb.PhaseSixteenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: developer.workflow.phoenix_mix_surface
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original_workbench_loader =
      Application.get_env(:jido_code, :workbench_inventory_loader, :__missing__)

    original_support_agent_updater =
      Application.get_env(:jido_code, :support_agent_config_project_updater, :__missing__)

    original_system_config_loader =
      Application.get_env(:jido_code, :system_config_loader, :__missing__)

    Application.put_env(:jido_code, :system_config_loader, fn ->
      {:ok,
       %{
         onboarding_completed: true,
         onboarding_step: 8,
         onboarding_state: %{},
         default_environment: :sprite,
         workspace_root: nil
       }}
    end)

    on_exit(fn ->
      restore_env(:workbench_inventory_loader, original_workbench_loader)
      restore_env(:support_agent_config_project_updater, original_support_agent_updater)
      restore_env(:system_config_loader, original_system_config_loader)
    end)

    :ok
  end

  test "repo start paths and contributor docs converge on the repo-owned mix server flow" do
    readme = repo_file!("README.md")
    contributing = repo_file!("CONTRIBUTING.md")
    tauri_readme = repo_file!("tauri/README.md")
    mixfile = repo_file!("mix.exs")
    workflow_spec = repo_file!(".spec/specs/developer_workflow.spec.md")
    package_spec = repo_file!(".spec/specs/package_quality_standards.spec.md")
    phase_plan = repo_file!(".spec/planning/phase-16-internal-cleanup-and-ui-convergence-foundation.md")

    assert readme =~ "mix server"
    assert contributing =~ "mix server"
    assert tauri_readme =~ "mix server"
    refute readme =~ "mix phx.server"
    refute contributing =~ "mix phx.server"
    refute tauri_readme =~ "mix phx.server"
    assert mixfile =~ "server: [\"frontend.start\", \"phx.server\"]"
    assert workflow_spec =~ "mix server"
    assert package_spec =~ "mix server"
    assert phase_plan =~ "[x] 16 Phase 16 - Internal Cleanup and UI Convergence Foundation"
    assert phase_plan =~ "[x] 16.3 Section - Phase 16 Integration Tests"
  end

  test "hybrid and plain liveview operator surfaces share the standardized notice structure", %{
    conn: _conn
  } do
    register_owner("phase16-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase16-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok, [],
       %{
         error_type: "workbench_inventory_stale",
         detail: "Workbench data is behind the latest repository updates.",
         remediation: "Retry the inventory refresh after verifying setup diagnostics."
       }}
    end)

    %{managed_repo: managed_repo} =
      provision_managed_repo!(%{
        name: "phase16-agent-project",
        github_full_name: "owner/phase16-agent-project",
        default_branch: "main",
        integration_settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => true}
          }
        }
      })

    Application.put_env(:jido_code, :support_agent_config_project_updater, fn _project, _attrs ->
      {:error, :forced_support_agent_config_failure}
    end)

    {:ok, workbench_view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(workbench_view, "#workbench-stale-warning-label", "Workbench data may be stale")
    assert has_element?(workbench_view, "#workbench-stale-warning-type", "workbench_inventory_stale")

    assert has_element?(
             workbench_view,
             "#workbench-stale-warning-detail",
             "Workbench data is behind the latest repository updates."
           )

    assert has_element?(
             workbench_view,
             "#workbench-stale-warning-remediation",
             "Retry the inventory refresh after verifying setup diagnostics."
           )

    {:ok, agents_view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    agents_view
    |> element("#agents-issue-bot-disable-#{managed_repo.id}")
    |> render_click()

    assert has_element?(
             agents_view,
             "#agents-issue-bot-error-label",
             "Issue Bot configuration update failed"
           )

    assert has_element?(
             agents_view,
             "#agents-issue-bot-error-type",
             "support_agent_config_persistence_failed"
           )

    assert has_element?(
             agents_view,
             "#agents-issue-bot-error-detail",
             "Issue Bot configuration persistence failed"
           )

    assert has_element?(
             agents_view,
             "#agents-issue-bot-error-remediation",
             "Retry the Issue Bot toggle. If this persists, verify repository settings persistence health."
           )
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
