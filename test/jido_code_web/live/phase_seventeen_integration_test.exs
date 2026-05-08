defmodule JidoCodeWeb.PhaseSeventeenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: baseline.surface.product_routes_declared
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RepoPosture
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  setup do
    original_system_config_loader =
      Application.get_env(:jido_code, :system_config_loader, :__missing__)

    on_exit(fn ->
      restore_env(:system_config_loader, original_system_config_loader)
    end)

    :ok
  end

  test "removed compatibility routes and docs stay absent while canonical repo surfaces remain advertised",
       %{conn: conn} do
    assert conn |> get("/projects") |> html_response(404)
    assert build_conn() |> get("/projects/legacy-repo") |> html_response(404)
    assert build_conn() |> get("/projects/legacy-repo/runs/legacy-run") |> html_response(404)

    router = repo_file!("lib/jido_code_web/router.ex")
    readme = repo_file!("README.md")
    contributing = repo_file!("CONTRIBUTING.md")
    agents = repo_file!("AGENTS.md")
    phase_plan = repo_file!(".planning/phase-17-compatibility-era-removal-and-canonical-cutover.md")

    assert router =~ ~s|live("/repos", ProjectInventoryLive, :index)|
    assert router =~ ~s|live("/repos/:id", ProjectDetailLive, :show)|
    assert router =~ ~s|live("/repos/:id/runs/:run_id", RunDetailLive, :show)|
    refute router =~ ~s|live("/projects"|

    refute readme =~ "/projects"
    refute contributing =~ "/projects"
    refute agents =~ "/projects"
    refute readme =~ "compatibility rollout"
    refute contributing =~ "compatibility rollout"
    refute agents =~ "compatibility rollout"

    refute File.exists?(Path.expand("lib/jido_code/control/compatibility_rollout.ex", repo_root()))
    refute File.exists?(Path.expand("test/jido_code/control/compatibility_rollout_test.exs", repo_root()))
    refute File.exists?(Path.expand("test/jido_code_web/live/phase_six_integration_test.exs", repo_root()))

    assert phase_plan =~ "[x] 17 Phase 17 - Compatibility Era Removal and Canonical Cutover"
    assert phase_plan =~ "[x] 17.4 Section - Phase 17 Integration Tests"
  end

  test "fresh bootstrap and canonical repo and run flows work without compatibility shims",
       %{conn: conn} do
    Application.put_env(:jido_code, :system_config_loader, fn ->
      {:ok,
       %{
         onboarding_completed: false,
         onboarding_step: 1,
         onboarding_state: %{},
         default_environment: :sprite,
         workspace_root: nil
       }}
    end)

    {:ok, _welcome_view, welcome_html} = live(conn, ~p"/welcome")
    assert welcome_html =~ "Create your admin account"
    assert {:error, {:live_redirect, %{to: "/welcome"}}} = live(conn, ~p"/setup", on_error: :warn)

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

    register_owner("phase17-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase17-owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "repo-phase17-canonical",
        github_full_name: "owner/repo-phase17-canonical",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, inventory_view, _html} = live(recycle(authed_conn), ~p"/repos", on_error: :warn)

    assert has_element?(inventory_view, "#project-inventory-table")
    assert has_element?(inventory_view, "h1", "Repositories")

    assert render(inventory_view) =~ ~s(href="/repos/#{managed_repo.id})

    {:ok, detail_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{managed_repo.id}", on_error: :warn)

    assert has_element?(detail_view, "#project-detail-title", "Managed repo detail")
    refute render(detail_view) =~ "Start conversation"

    run_id = "run-phase17-canonical-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Phase 17 canonical run surface"},
        input_metadata: %{"task_summary" => %{required: true, source: "integration_test"}},
        initiating_actor: %{id: "owner-1", email: "phase17-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-04 12:00:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-04-04 12:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-04 12:02:00Z]
      })

    {:ok, _repo_posture} =
      RepoPosture.upsert_for_managed_repo(
        %{
          managed_repo_id: managed_repo.id,
          summary: "Repo posture remains governed.",
          overall_trust: "medium",
          execution_readiness: "medium",
          validation_reliability: "high",
          review_burden: "high",
          drift_rate: "low",
          recovery_resilience: "medium",
          requirements_confidence: "high",
          supervision_mode: "guided",
          escalation_status: "review",
          contributing_check_ids: [],
          posture_metadata: %{
            "runtime_service_evidence_summary" =>
              "Runtime delivery remains bounded to product evidence after compatibility seams were removed.",
            "runtime_service_evidence_state" => %{
              "status" => "degraded",
              "runtime_delivery" => %{
                "delivery_mode" => "live_subscription",
                "reason_code" => "terminal_review_required"
              },
              "integration_outcomes" => %{
                "latest_invocation" => %{
                  "provider" => "github",
                  "summary" => "github delivery remained canonical"
                }
              }
            }
          }
        },
        actor: Actor.operator_actor()
      )

    {:ok, run_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{managed_repo.id}/runs/#{run_id}", on_error: :warn)

    assert has_element?(run_view, "#run-detail-title", "Run detail")
    assert has_element?(run_view, "#run-detail-status", "awaiting_approval")
    assert has_element?(run_view, "#run-detail-runtime-evidence")

    assert has_element?(
             run_view,
             "#run-detail-runtime-evidence-summary",
             "Runtime delivery remains bounded to product evidence after compatibility seams were removed."
           )

    assert has_element?(run_view, "#run-detail-runtime-evidence-status", "review required")
    assert has_element?(run_view, "#run-detail-runtime-evidence-delivery-mode", "live subscription")
    assert has_element?(run_view, "#run-detail-runtime-evidence-reason", "terminal review required")
    assert has_element?(run_view, "#run-detail-runtime-evidence-integration", "github delivery remained canonical")
    assert has_element?(run_view, "#run-detail-runtime-evidence-note", "runtime transport remains opaque")

    rendered_run_detail = render(run_view)
    refute rendered_run_detail =~ "/projects/"
    refute rendered_run_detail =~ "compatibility rollout"
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-17-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
