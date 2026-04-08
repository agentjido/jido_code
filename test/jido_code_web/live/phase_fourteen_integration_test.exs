defmodule JidoCodeWeb.PhaseFourteenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RepoPosture
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  setup do
    original_workbench_loader =
      Application.get_env(:jido_code, :workbench_inventory_loader, :__missing__)

    on_exit(fn ->
      restore_env(:workbench_inventory_loader, original_workbench_loader)
    end)

    :ok
  end

  test "settings overview keeps the route liveview-owned while exposing bounded vue interaction", %{
    conn: _conn
  } do
    register_owner("phase14-settings-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase14-settings-owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/github", on_error: :warn)

    widget = assert_vue_component(view, "SettingsOverviewWidget", id: "settings-overview-widget")

    assert widget.props["activeTab"] == "github"
    assert widget.props["openAddRepoVisible"] == true
    assert_vue_handler(view, "openAddRepo", "open_add_modal", id: "settings-overview-widget")

    assert has_element?(view, "button[phx-click='open_add_modal']", "Add Repository")
    refute has_element?(view, "#add-repo-modal")

    view
    |> element("button[phx-click='open_add_modal']")
    |> render_click()

    assert has_element?(view, "#add-repo-modal")
  end

  test "workbench summary widget tracks liveview-owned filter state changes", %{conn: _conn} do
    register_owner("phase14-workbench-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase14-workbench-owner@example.com", "owner-password-123")

    now = DateTime.utc_now()

    Application.put_env(:jido_code, :workbench_inventory_loader, fn ->
      {:ok,
       [
         %{
           id: "owner-repo-alpha",
           name: "repo-alpha",
           github_full_name: "owner/repo-alpha",
           open_issue_count: 5,
           open_pr_count: 0,
           recent_activity_summary: "Alpha summary",
           recent_activity_at: DateTime.add(now, -45 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-beta",
           name: "repo-beta",
           github_full_name: "owner/repo-beta",
           open_issue_count: 0,
           open_pr_count: 4,
           recent_activity_summary: "Beta summary",
           recent_activity_at: DateTime.add(now, -2 * 60 * 60, :second) |> DateTime.to_iso8601()
         },
         %{
           id: "owner-repo-gamma",
           name: "repo-gamma",
           github_full_name: "owner/repo-gamma",
           open_issue_count: 2,
           open_pr_count: 1,
           recent_activity_summary: "Gamma summary",
           recent_activity_at: DateTime.add(now, -10 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()
         }
       ], nil}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    widget = assert_vue_component(view, "WorkbenchSummaryWidget", id: "workbench-summary-widget")

    assert widget.props["inventoryCount"] == 3
    assert widget.props["inventoryTotalCount"] == 3
    assert widget.props["resetVisible"] == false
    assert_vue_handler(view, "resetFilters", "reset_filters", id: "workbench-summary-widget")

    assert has_element?(view, "#workbench-filters-form")
    assert has_element?(view, "#workbench-filter-results-count", "Showing 3 of 3")

    apply_workbench_filters(view, %{"project_id" => "owner-repo-beta"})

    updated_widget = vue(view, id: "workbench-summary-widget")

    assert updated_widget.props["inventoryCount"] == 1
    assert updated_widget.props["resetVisible"] == true
    assert has_element?(view, "#workbench-project-name-owner-repo-beta", "owner/repo-beta")
    refute has_element?(view, "#workbench-project-name-owner-repo-alpha")
  end

  test "repo detail overview keeps workflow state server-authored", %{conn: _conn} do
    register_owner("phase14-project-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase14-project-owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "repo-phase14-project-detail",
        github_full_name: "owner/repo-phase14-project-detail",
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

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    widget =
      assert_vue_component(view, "ProjectDetailOverviewWidget", id: "project-detail-overview-widget")

    assert widget.props["githubFullName"] == "owner/repo-phase14-project-detail"
    assert widget.props["launchReady"] == true
    assert length(widget.props["workflowCards"]) == 2
    refute render(view) =~ "Start conversation"
  end

  test "run detail governance overview keeps runtime evidence bounded and product-oriented", %{
    conn: _conn
  } do
    register_owner("phase14-run-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase14-run-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-phase14-run-detail",
        github_full_name: "owner/repo-phase14-run-detail",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-phase14-detail-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render governed runtime evidence."},
        input_metadata: %{"task_summary" => %{required: true, source: "test"}},
        initiating_actor: %{id: "owner-1", email: "phase14-run-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-01 12:00:00Z],
        step_results: %{
          "diff_summary" => "2 files changed (+9/-1).",
          "runtime_service_delivery" => %{
            "delivery_mode" => "replay_recovery",
            "reason_code" => "live_delivery_detached",
            "terminal_handoff_kind" => "replay_terminal_lookup",
            "terminal_state" => "completed",
            "summary" => "Runtime delivery repaired through replay recovery."
          }
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-04-01 12:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-01 12:02:00Z]
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

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
              "Runtime evidence requires operator review before execution trust can be restored.",
            "runtime_service_evidence_state" => %{
              "status" => "degraded",
              "review_required" => true,
              "runtime_delivery" => %{
                "delivery_mode" => "replay_recovery",
                "reason_code" => "live_delivery_detached"
              },
              "integration_outcomes" => %{
                "latest_invocation" => %{
                  "provider" => "github",
                  "summary" => "github installation delivery recovered"
                }
              }
            }
          }
        },
        actor: Actor.operator_actor()
      )

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    widget =
      assert_vue_component(
        view,
        "RunGovernanceOverviewWidget",
        id: "run-detail-governance-overview-widget"
      )

    assert widget.props["runStatus"] == "awaiting_approval"
    assert widget.props["runtimeEvidence"]["statusLabel"] == "review required"
    refute Map.has_key?(widget.props["runtimeEvidence"], "turnId")
    refute Map.has_key?(widget.props["runtimeEvidence"], "sessionId")

    assert has_element?(view, "#run-detail-runtime-evidence")

    assert has_element?(
             view,
             "#run-detail-runtime-evidence-summary",
             "operator review before execution trust can be restored"
           )

    assert has_element?(view, "#run-detail-runtime-evidence-note", "Product governance stores bounded runtime evidence")
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-14-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp apply_workbench_filters(view, overrides) do
    filter_params = Map.merge(default_workbench_filter_params(), overrides)

    view
    |> element("#workbench-filters-form")
    |> render_change(%{"filters" => filter_params})
  end

  defp default_workbench_filter_params do
    %{
      "project_id" => "all",
      "work_state" => "all",
      "freshness_window" => "any",
      "sort_order" => "project_name_asc"
    }
  end
end
