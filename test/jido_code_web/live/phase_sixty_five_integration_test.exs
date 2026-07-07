defmodule JidoCodeWeb.PhaseSixtyFiveIntegrationTest do
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

  test "65.5.1 dashboard concern tabs keep one authenticated route while bounded panels switch in place",
       %{conn: _conn} do
    register_owner("phase65-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase65-owner@example.com", "owner-password-123")

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?onboarding=completed", on_error: :warn)

    assert has_element?(view, "#dashboard-root[data-dashboard-section='overview']")
    assert has_element?(view, "#dashboard-overview-panel")
    assert has_element?(view, "#dashboard-section-nav-next_steps")

    view
    |> element("#dashboard-section-nav-runs")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=runs&subject=work")
    assert has_element?(view, "#dashboard-root[data-dashboard-section='runs']")
    assert has_element?(view, "#dashboard-run-summaries")
    refute has_element?(view, "#dashboard-overview-panel")
    refute has_element?(view, "#dashboard-conversation-supervision")

    view
    |> element("#dashboard-section-nav-conversations")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=conversations&subject=work")
    assert has_element?(view, "#dashboard-root[data-dashboard-section='conversations']")
    assert has_element?(view, "#dashboard-conversation-supervision")
    refute has_element?(view, "#dashboard-run-summaries")

    view
    |> element("#dashboard-shell-section-groups-knowledge")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=memory&subject=knowledge")
    assert has_element?(view, "#dashboard-root[data-dashboard-subject='knowledge'][data-dashboard-section='memory']")
    assert has_element?(view, "#dashboard-memory-summaries")
    refute has_element?(view, "#dashboard-conversation-supervision")

    view
    |> element("#dashboard-shell-section-groups-runtime")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=runtime&subject=runtime")
    assert has_element?(view, "#dashboard-root[data-dashboard-subject='runtime'][data-dashboard-section='runtime']")
    assert has_element?(view, "#dashboard-runtime-evidence")
    refute has_element?(view, "#dashboard-memory-summaries")

    view
    |> element("#dashboard-shell-section-groups-work")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=overview&subject=work")

    view
    |> element("#dashboard-section-nav-next_steps")
    |> render_click()

    assert_patch(view, "/dashboard?onboarding=completed&section=next_steps&subject=work")
    assert has_element?(view, "#dashboard-root[data-dashboard-section='next_steps']")
    assert has_element?(view, "#dashboard-onboarding-next-actions")
    refute has_element?(view, "#dashboard-runtime-evidence")
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "65.5.2 phase 65 plan, ADR, specs, and browser coverage remain aligned" do
    phase_plan =
      repo_file!(".planning/phase-65-dashboard-concern-tab-information-architecture.md")

    adr = repo_file!(".spec/decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md")

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

    assert phase_plan =~ "[x] 65 Phase 65 - Dashboard Concern Tab Information Architecture"
    assert phase_plan =~ "[x] 65.1 Section - Canonical Concern Families And Route Ownership"
    assert phase_plan =~ "[x] 65.2 Section - Tab Shell And Overview Handoff"
    assert phase_plan =~ "[x] 65.3 Section - Concern Panel Separation"
    assert phase_plan =~ "[x] 65.4 Section - Current-Truth And Helper Convergence"
    assert phase_plan =~ "[x] 65.5 Section - Phase Integration Tests"

    assert adr =~ "This decision is now landed in product code."
    assert adr =~ "route-owned `section` selection"
    assert adr =~ "evolved from a top rail into left-sidebar"

    assert monitoring_adr =~ "Phase 66 has landed"
    assert monitoring_adr =~ "repository-first"
    assert monitoring_adr =~ "monitoring feed that orders overview entries"

    assert baseline_spec =~ "left-sidebar concern navigation"
    assert baseline_spec =~ "durable authenticated landing"

    assert factory_spec =~ "left-sidebar concern navigation"
    assert factory_spec =~ "test/jido_code_web/live/phase_sixty_five_integration_test.exs"

    assert frontend_spec =~ "dashboard as a LiveView-owned authenticated landing"
    assert frontend_spec =~ "repository-first overview"
    assert frontend_spec =~ "test/jido_code_web/live/phase_sixty_five_integration_test.exs"
    assert frontend_spec =~ "test/e2e/dashboard-tabs.spec.ts"

    assert conversation_spec =~ "sidebar-selected dashboard conversation concern"
    assert conversation_spec =~ "test/jido_code_web/live/phase_sixty_five_integration_test.exs"

    assert memory_spec =~ "sidebar-selected dashboard memory concern"
    assert memory_spec =~ "test/jido_code_web/live/phase_sixty_five_integration_test.exs"

    assert repo_posture_spec =~ "sidebar-selected runtime and posture concern"
    assert repo_posture_spec =~ "test/jido_code_web/live/phase_sixty_five_integration_test.exs"

    assert runtime_spec =~ "authenticated left-sidebar runtime concern"
    assert runtime_spec =~ "test/jido_code_web/live/phase_sixty_five_integration_test.exs"

    assert package_spec =~ ".planning/phase-65-dashboard-concern-tab-information-architecture.md"
    assert package_spec =~ "test/jido_code_web/live/phase_sixty_five_integration_test.exs"
    assert package_spec =~ "test/e2e/dashboard-tabs.spec.ts"

    assert browser_spec =~
             "dashboard sidebar keeps the ready-state landing route scanable on wide screens"

    assert browser_spec =~
             "dashboard sidebar navigation stays usable as a wrapped fallback on narrow screens"
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
