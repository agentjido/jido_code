defmodule JidoCodeWeb.PhaseSixtySixIntegrationTest do
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

  test "66.3.1 dashboard keeps one route while overview becomes a sidebar-led repository monitoring list",
       %{conn: _conn} do
    register_owner("phase66-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase66-owner@example.com", "owner-password-123")

    %{route_id: older_route_id} =
      provision_managed_repo!(%{
        name: "repo-phase66-older",
        github_full_name: "owner/repo-phase66-older",
        default_branch: "main",
        settings: %{}
      })

    %{route_id: newer_route_id} =
      provision_managed_repo!(%{
        name: "repo-phase66-newer",
        github_full_name: "owner/repo-phase66-newer",
        default_branch: "main",
        settings: %{}
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, _older_run} =
      create_run(older_route_id, "phase66-older-run", DateTime.add(now, -6_000, :second), %{
        status: :completed,
        current_step: "publish_pr",
        current_stage: "publish_pr",
        completed_at: DateTime.add(now, -5_940, :second)
      })

    {:ok, _newer_run} =
      create_run(newer_route_id, "phase66-newer-run", DateTime.add(now, -600, :second), %{
        status: :running,
        current_step: "implement",
        current_stage: "implement"
      })

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?onboarding=completed", on_error: :warn)

    html = render(view)

    assert has_element?(view, "#dashboard-root[data-dashboard-section='overview']")
    assert has_element?(view, "#dashboard-sidebar-shell")
    assert has_element?(view, "#dashboard-section-nav-next_steps")
    assert has_element?(view, "#dashboard-overview-repository-list", "owner/repo-phase66-newer")
    assert has_element?(view, "#dashboard-overview-repository-list", "Recent run outcome")
    assert has_element?(view, "#dashboard-overview-repository-list", "running")
    assert has_element?(view, "#dashboard-overview-repository-list", "phase66-newer-run")

    assert string_position(html, "owner/repo-phase66-newer") <
             string_position(html, "owner/repo-phase66-older")

    view
    |> element("#dashboard-shell-parent-subjects-runtime")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=runtime&subject=runtime")
    assert has_element?(view, "#dashboard-root[data-dashboard-subject='runtime'][data-dashboard-section='runtime']")
    assert has_element?(view, "#dashboard-runtime-evidence")
    refute has_element?(view, "#dashboard-overview-panel")

    view
    |> element("#dashboard-shell-parent-subjects-work")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=overview&subject=work")
    assert has_element?(view, "#dashboard-overview-panel")
    assert has_element?(view, "#dashboard-overview-repository-list")
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "66.3.2 phase 66 plan, ADRs, specs, and browser coverage remain aligned" do
    phase_plan =
      repo_file!(".planning/phase-66-dashboard-sidebar-and-repository-monitoring-foundation.md")

    concern_adr = repo_file!(".spec/decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md")
    monitoring_adr = repo_file!(".spec/decisions/jido_code.dashboard_developer_centric_monitoring_sidebar.md")
    baseline_spec = repo_file!(".spec/specs/baseline_surface.spec.md")
    factory_spec = repo_file!(".spec/specs/factory_control_plane.spec.md")
    frontend_spec = repo_file!(".spec/specs/frontend_architecture.spec.md")
    conversation_spec = repo_file!(".spec/specs/conversation_orchestration.spec.md")
    memory_spec = repo_file!(".spec/specs/memory_graph_surface_rollout_and_governance_actions.spec.md")
    repo_posture_spec = repo_file!(".spec/specs/repo_posture.spec.md")
    runtime_spec = repo_file!(".spec/specs/runtime_service_overlay.spec.md")
    package_spec = repo_file!(".spec/specs/package.spec.md")
    browser_spec = repo_file!("test/e2e/dashboard-tabs.spec.ts")

    assert phase_plan =~ "[x] 66 Phase 66 - Dashboard Sidebar And Repository Monitoring Foundation"
    assert phase_plan =~ "[x] 66.1 Section - Sidebar Navigation And Route Ownership"
    assert phase_plan =~ "[x] 66.2 Section - Repository-First Overview Feed Foundation"
    assert phase_plan =~ "[x] 66.3 Section - Phase Integration Tests"

    assert concern_adr =~ "This decision is now landed in product code."
    assert concern_adr =~ "evolved from a top rail into left-sidebar"

    assert monitoring_adr =~ "Phase 66 has landed"
    assert monitoring_adr =~ "left sidebar that acts as the canonical tab rail"
    assert monitoring_adr =~ "repository-first"
    assert monitoring_adr =~ "monitoring feed that orders overview entries"

    assert baseline_spec =~ "left-sidebar concern navigation"
    assert baseline_spec =~ "repository-first overview"

    assert factory_spec =~ "left-sidebar concern navigation"
    assert factory_spec =~ "repository-first monitoring overview"
    assert factory_spec =~ "test/jido_code_web/live/phase_sixty_six_integration_test.exs"

    assert frontend_spec =~ "left-sidebar concern navigation"
    assert frontend_spec =~ "repository-first overview"
    assert frontend_spec =~ "test/jido_code_web/live/phase_sixty_six_integration_test.exs"
    assert frontend_spec =~ "test/e2e/dashboard-tabs.spec.ts"

    assert conversation_spec =~ "sidebar-selected dashboard conversation concern"
    assert conversation_spec =~ "test/jido_code_web/live/phase_sixty_six_integration_test.exs"

    assert memory_spec =~ "sidebar-selected dashboard memory concern"
    assert memory_spec =~ "test/jido_code_web/live/phase_sixty_six_integration_test.exs"

    assert repo_posture_spec =~ "sidebar-selected runtime and posture concern"
    assert repo_posture_spec =~ "test/jido_code_web/live/phase_sixty_six_integration_test.exs"

    assert runtime_spec =~ "left-sidebar runtime concern"
    assert runtime_spec =~ "test/jido_code_web/live/phase_sixty_six_integration_test.exs"

    assert package_spec =~ ".planning/phase-66-dashboard-sidebar-and-repository-monitoring-foundation.md"
    assert package_spec =~ "test/jido_code_web/live/phase_sixty_six_integration_test.exs"
    assert package_spec =~ "test/e2e/dashboard-tabs.spec.ts"

    assert browser_spec =~
             "dashboard sidebar keeps the ready-state landing route scanable on wide screens"

    assert browser_spec =~
             "dashboard sidebar navigation stays usable as a wrapped fallback on narrow screens"
  end

  defp create_run(repo_identifier, run_id, started_at, attrs) do
    {:ok, repo_scope} = RepoBridge.repo_scope(repo_identifier)

    {:ok, project} =
      Project.create(
        %{
          name: "phase66-#{run_id}",
          source_kind: :local,
          local_path: "/tmp/phase66-#{run_id}"
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
        inputs: %{"task_summary" => "Render dashboard monitoring order"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "phase66-owner@example.com"},
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

  defp string_position(haystack, needle) do
    case :binary.match(haystack, needle) do
      {position, _length} -> position
      :nomatch -> flunk("expected #{inspect(needle)} to appear in rendered output")
    end
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
