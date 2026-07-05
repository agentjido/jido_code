defmodule JidoCodeWeb.PhaseSixtySevenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.Actor
  alias JidoCode.Control.RepoBridge
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project

  setup do
    original_runtime_loader =
      Application.get_env(:jido_code, :dashboard_runtime_evidence_loader, :__missing__)

    original_memory_loader =
      Application.get_env(:jido_code, :dashboard_memory_summary_loader, :__missing__)

    original_conversation_loader =
      Application.get_env(:jido_code, :dashboard_conversation_summary_loader, :__missing__)

    on_exit(fn ->
      restore_env(:dashboard_runtime_evidence_loader, original_runtime_loader)
      restore_env(:dashboard_memory_summary_loader, original_memory_loader)
      restore_env(:dashboard_conversation_summary_loader, original_conversation_loader)
    end)

    :ok
  end

  test "67.4.1 dashboard overview renders split monitoring panels with bounded accordions", %{
    conn: _conn
  } do
    register_owner("phase67-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase67-owner@example.com", "owner-password-123")

    %{route_id: route_id, managed_repo: managed_repo} =
      provision_managed_repo!(%{
        name: "repo-phase67",
        github_full_name: "owner/repo-phase67",
        default_branch: "main",
        settings: %{}
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, _run} =
      create_run(route_id, "phase67-run", DateTime.add(now, -600, :second), %{
        status: :awaiting_approval,
        current_step: "publish_pr",
        current_stage: "approval"
      })

    Application.put_env(:jido_code, :dashboard_conversation_summary_loader, fn ->
      {:ok,
       [
         %{
           id: "phase67-conversation-summary",
           route_id: route_id,
           managed_repo_id: managed_repo.id,
           repo_label: "owner/repo-phase67",
           role_scope: "work_item_scoped",
           role_attachment_mode: "governed_work",
           role_work_item_id: "work-item-phase67",
           latest_status: "active",
           active_count: 2,
           clarification_count: 1,
           detail: "2 governed conversations active. 1 clarification turn needs an answer.",
           latest_activity_at: now,
           route: "/repos/#{route_id}#project-detail-conversation-panel",
           action_label: "Open governed supervision"
         }
       ], nil}
    end)

    Application.put_env(:jido_code, :dashboard_memory_summary_loader, fn ->
      {:ok,
       [
         %{
           id: "phase67-memory-summary",
           route_id: route_id,
           managed_repo_id: managed_repo.id,
           repo_label: "owner/repo-phase67",
           state: "invalidated",
           label: "Memory graph invalidated",
           detail: "Repository memory graph validation was explicitly invalidated.",
           remediation: "Validate repository memory graph for the current revision.",
           memory_count: 4,
           provenance_count: 3,
           route: "/repos/#{route_id}#project-detail-memory-inspection",
           action_label: "Validate memory graph",
           action_needed?: true
         }
       ], nil}
    end)

    Application.put_env(:jido_code, :dashboard_runtime_evidence_loader, fn ->
      {:ok,
       [
         %{
           id: "phase67-runtime-summary",
           managed_repo_id: managed_repo.id,
           repo_label: "owner/repo-phase67",
           status: "blocked",
           summary: "Runtime delivery is blocked until repository workspace binding is repaired.",
           delivery_mode: "guided",
           reason_code: "workspace_binding_missing",
           latest_provider: "github",
           supervision_mode: "guided",
           review_required: true,
           updated_at: now
         }
       ], nil}
    end)

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?onboarding=completed", on_error: :warn)

    repo_dom_token = run_dom_token(route_id)

    assert has_element?(view, "#dashboard-root[data-dashboard-section='overview']")
    assert has_element?(view, "#dashboard-overview-repository-card-#{repo_dom_token}")
    assert has_element?(view, "#dashboard-overview-repository-label-#{repo_dom_token}", "owner/repo-phase67")
    assert has_element?(view, "#dashboard-overview-repository-badge-runtime-#{repo_dom_token}")
    assert has_element?(view, "#dashboard-overview-repository-semantic-hint-recovery-#{repo_dom_token}")
    assert has_element?(view, "#dashboard-overview-repository-memory-hint-recovery-#{repo_dom_token}")

    assert has_element?(
             view,
             "#dashboard-overview-repository-issues-run-outcome-#{repo_dom_token}-link",
             "Open run detail"
           )

    assert has_element?(
             view,
             "#dashboard-overview-repository-issues-project-link-#{repo_dom_token}[href^=\"/repos/#{route_id}\"]",
             "Repo detail"
           )

    assert has_element?(
             view,
             "#dashboard-overview-repository-prs-project-link-#{repo_dom_token}[href^=\"/repos/#{route_id}\"]",
             "Repo detail"
           )
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "67.4.2 phase 67 plan, ADR, specs, and browser coverage remain aligned" do
    phase_plan =
      repo_file!(".planning/phase-67-dashboard-repository-panels-and-accordion-monitoring.md")

    concern_adr =
      repo_file!(".spec/decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md")

    monitoring_adr =
      repo_file!(".spec/decisions/jido_code.dashboard_developer_centric_monitoring_sidebar.md")

    baseline_spec = repo_file!(".spec/specs/baseline_surface.spec.md")
    factory_spec = repo_file!(".spec/specs/factory_control_plane.spec.md")
    frontend_spec = repo_file!(".spec/specs/frontend_architecture.spec.md")
    conversation_spec = repo_file!(".spec/specs/conversation_orchestration.spec.md")
    memory_spec = repo_file!(".spec/specs/memory_graph_surface_rollout_and_governance_actions.spec.md")
    repo_posture_spec = repo_file!(".spec/specs/repo_posture.spec.md")
    runtime_spec = repo_file!(".spec/specs/runtime_service_overlay.spec.md")
    package_spec = repo_file!(".spec/specs/package.spec.md")
    browser_spec = repo_file!("test/e2e/dashboard-tabs.spec.ts")

    assert phase_plan =~ "[x] 67.1 Section - Split Repository Panel Composition"
    assert phase_plan =~ "[x] 67.2 Section - Accordion Detail And Bounded Concern Handoff"
    assert phase_plan =~ "[x] 67.3 Section - Current-Truth And Helper Convergence"

    assert concern_adr =~ "route-owned `section` selection"
    assert concern_adr =~ "left-sidebar"

    assert monitoring_adr =~ "Phase 67 has now landed"
    assert monitoring_adr =~ "borderless monitoring panel"
    assert monitoring_adr =~ "bounded LiveView-owned accordion region"

    assert baseline_spec =~ "split monitoring panels plus bounded in-place accordions"
    assert factory_spec =~ "bounded per-repository accordions"
    assert frontend_spec =~ "split monitoring panels plus LiveView-owned accordions"
    assert conversation_spec =~ "overview accordion"
    assert memory_spec =~ "overview accordions"
    assert repo_posture_spec =~ "overview's bounded in-place monitoring accordions"
    assert runtime_spec =~ "overview accordions"
    assert package_spec =~ "phase-67 split-panel accordion monitoring convergence"

    assert browser_spec =~
             "dashboard overview repository panels expand bounded monitoring detail on wide screens"

    assert browser_spec =~
             "dashboard overview repository accordions stay usable on narrow screens"
  end

  defp create_run(repo_identifier, run_id, started_at, attrs) do
    {:ok, repo_scope} = RepoBridge.repo_scope(repo_identifier)

    {:ok, project} =
      Project.create(
        %{
          name: "phase67-#{run_id}",
          source_kind: :local,
          local_path: "/tmp/phase67-#{run_id}"
        },
        actor: Actor.operator_actor()
      )

    workflow_attrs =
      %{
        project_id: project.id,
        managed_repo_id: repo_scope.managed_repo.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render dashboard monitoring accordion"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "phase67-owner@example.com"},
        current_step: "queued",
        started_at: started_at
      }

    {:ok, workflow_run} = WorkflowRun.create(workflow_attrs, actor: Actor.operator_actor())

    final_workflow_run =
      workflow_run
      |> maybe_transition_to_running(attrs, started_at)
      |> maybe_transition_to_terminal(attrs, started_at)

    Run.get_by_workflow_run_id(final_workflow_run.id, actor: Actor.operator_actor())
  end

  defp maybe_transition_to_running(workflow_run, attrs, started_at) do
    desired_status = Map.get(attrs, :status, :pending)

    if desired_status in [:running, :awaiting_approval, :completed, :failed, :cancelled] do
      {:ok, workflow_run} =
        WorkflowRun.transition_status(
          workflow_run,
          %{
            to_status: :running,
            current_step: Map.get(attrs, :current_step, "queued"),
            transitioned_at: DateTime.add(started_at, 1, :second)
          },
          actor: Actor.operator_actor()
        )

      workflow_run
    else
      workflow_run
    end
  end

  defp maybe_transition_to_terminal(%WorkflowRun{} = workflow_run, attrs, started_at) do
    case Map.get(attrs, :status, :pending) do
      status when status in [:awaiting_approval, :completed, :failed, :cancelled] ->
        {:ok, workflow_run} =
          WorkflowRun.transition_status(
            workflow_run,
            %{
              to_status: status,
              current_step: Map.get(attrs, :current_step, workflow_run.current_step),
              transitioned_at: Map.get(attrs, :completed_at) || DateTime.add(started_at, 60, :second)
            },
            actor: Actor.operator_actor()
          )

        workflow_run

      _other ->
        workflow_run
    end
  end

  defp run_dom_token(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
