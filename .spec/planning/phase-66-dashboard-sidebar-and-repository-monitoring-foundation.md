# Phase 66 - Dashboard Sidebar And Repository Monitoring Foundation

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->
<!-- covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state -->
<!-- covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented -->
<!-- covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/repo_posture.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../specs/memory_graph_surface_rollout_and_governance_actions.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md`
- `../decisions/jido_code.dashboard_developer_centric_monitoring_sidebar.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md`
- `lib/jido_code/governance/runtime_evidence_feed.ex`
- `lib/jido_code/orchestration/run_summary_feed.ex`
- `lib/jido_code/workbench/dashboard_conversation_feed.ex`
- `lib/jido_code/memory_graph/dashboard_summary_feed.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/components/operator_state_components.ex`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/e2e/dashboard-tabs.spec.ts`

## Relevant Assumptions / Defaults
- Phase 65 is already landed and provides the current route-owned dashboard concern baseline.
- `/dashboard` remains the durable authenticated landing route for ready-state operators.
- The new ADR refines dashboard toward a developer-centric multi-project monitoring surface rather than replacing route ownership or turning dashboard into a client-owned application shell.
- Concern navigation should remain route-owned and product-shaped even as the chrome moves from top tabs to a left sidebar on wide screens.
- The first dashboard tab remains `Overview`, but it now needs to become repository-first and ordered by recent meaningful work activity instead of summary-first.

[x] 66 Phase 66 - Dashboard Sidebar And Repository Monitoring Foundation
  Reframe the authenticated dashboard around a developer-centric navigation and repository-monitoring foundation so operators can scan multiple repositories as a working set before the richer per-repository panel composition arrives.

  [x] 66.1 Section - Sidebar Navigation And Route Ownership
    Replace the current top-of-content dashboard concern rail with a left-sidebar model while preserving the existing route-owned section semantics and narrow-screen fallback behavior.

    [x] 66.1.1 Task - Adopt the left sidebar as the canonical dashboard concern navigator
      Establish the wide-screen dashboard shell that matches the new developer-centric ADR without introducing a second application shell.

      [x] 66.1.1.1 Subtask - Replace the current top concern rail with a left sidebar that owns `Overview`, `Runs`, `Conversations`, `Memory`, `Runtime`, and conditional `Next Steps`.
      [x] 66.1.1.2 Subtask - Preserve bounded badge or warning affordances on sidebar items so operators can still see counts or attention cues before opening a section.
      [x] 66.1.1.3 Subtask - Keep a narrow-screen fallback navigation path that preserves the same section ordering and route semantics without depending on the desktop sidebar layout.

    [x] 66.1.2 Task - Keep dashboard selection and framing LiveView-owned
      Preserve the current routed dashboard contract while changing the layout model around it.

      [x] 66.1.2.1 Subtask - Keep section selection in route-owned LiveView state such as the current patchable query-param contract rather than client-only tab state.
      [x] 66.1.2.2 Subtask - Keep dashboard authentication, summary-feed loading, and refresh behavior in the routed LiveView shell instead of moving them into client-owned sidebar logic.
      [x] 66.1.2.3 Subtask - Keep page title, signed-in orientation copy, and the settings handoff outside the sidebar-controlled concern body.

  [x] 66.2 Section - Repository-First Overview Feed Foundation
    Turn `Overview` from a summary-first landing panel into the repository-first monitoring scaffold that will anchor the developer-centric dashboard.

    [x] 66.2.1 Task - Define explainable repository recency ordering
      Make the overview list prioritize the repositories the operator most likely needs to inspect next.

      [x] 66.2.1.1 Subtask - Introduce a product-owned helper or feed boundary that derives per-repository “last worked on” ordering from meaningful governed or operator-facing activity instead of static repository metadata.
      [x] 66.2.1.2 Subtask - Keep the ordering explainable to operators so the dashboard can later show why one repository appears above another.
      [x] 66.2.1.3 Subtask - Preserve bounded empty-state behavior when no managed repositories or no recent activity are available.

    [x] 66.2.2 Task - Replace summary-first overview with a repository monitoring list scaffold
      Change the default dashboard landing so repositories become the primary scan unit.

      [x] 66.2.2.1 Subtask - Replace the current overview summary-card grid with an ordered list of repository monitoring entries.
      [x] 66.2.2.2 Subtask - Keep each repository entry bounded and monitoring-focused rather than embedding full repo-detail or workbench surfaces directly on dashboard.
      [x] 66.2.2.3 Subtask - Preserve direct handoff paths from overview entries back to canonical managed-repository and governed-run routes.

  [x] 66.3 Section - Phase Integration Tests
    Prove that the new sidebar shell and repository-first overview foundation improve scanability without breaking the current routed dashboard contract.

    [x] 66.3.1 Task - Add dashboard route coverage for sidebar navigation and repository ordering
      Verify the foundational developer-centric dashboard behavior at the route and browser levels.

      [x] 66.3.1.1 Subtask - Add LiveView coverage proving the left sidebar owns the same route-selected concern families as the earlier top-tab shell.
      [x] 66.3.1.2 Subtask - Add LiveView coverage proving `Overview` now defaults to a repository-ordered monitoring list rather than the prior summary-first grid.
      [x] 66.3.1.3 Subtask - Add browser coverage for wide-screen sidebar behavior and narrow-screen fallback navigation so the authenticated landing remains usable across supported viewports.
