# Phase 69 - Dashboard And Managed-Repo Subject-Tree Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell -->
<!-- covers: architecture.operator_surface_information_architecture.child_subject_tabs_live_in_left_sidebar -->
<!-- covers: architecture.operator_surface_information_architecture.route_breadcrumbs_sit_between_header_and_subject_navigation -->
<!-- covers: architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions -->
<!-- covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/operator_surface_information_architecture.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../specs/memory_graph_surface_rollout_and_governance_actions.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../decisions/jido_code.post_onboarding_subject_tree_operator_shell.md`
- `../planning/phase-61-managed-repo-detail-sidebar-information-architecture.md`
- `../planning/phase-65-dashboard-concern-tab-information-architecture.md`
- `../planning/phase-66-dashboard-sidebar-and-repository-monitoring-foundation.md`
- `../planning/phase-67-dashboard-repository-panels-and-accordion-monitoring.md`
- `../planning/phase-68-shared-post-onboarding-operator-shell-foundation.md`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `test/e2e/dashboard-tabs.spec.ts`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 68 provides the reusable breadcrumb, parent-subject, child-subject, and
  selected-pane framing helpers needed for route migration.
- Phases 61 and 65 remain valid historical foundations for route-owned family
  selection even though the accepted shell target has changed.
- Phases 66 and 67 remain useful only for still-relevant dashboard monitoring
  content ideas; their left-sidebar-first shell assumptions are superseded.
- Dashboard and managed-repository detail still use primary left-sidebar rails
  in current implementation, so both routes need explicit shell migration.
- Route-specific subject taxonomy should remain product-owned, terse, and
  patchable through LiveView route state instead of becoming client-owned UI
  memory.

[x] 69 Phase 69 - Dashboard And Managed-Repo Subject-Tree Adoption
  Migrate dashboard and managed-repository detail onto the shared subject-tree
  shell, define each route's parent and child subject taxonomy, and keep the
  accepted breadcrumb plus pane-framing model aligned with route behavior,
  helper boundaries, and verification.

  [x] 69.1 Section - Dashboard Subject-Tree Taxonomy And Migration
    Rebuild the authenticated landing route around parent and child subjects
    without discarding the still-useful dashboard content families or bounded
    handoff paths.

    [x] 69.1.1 Task - Establish the canonical dashboard subject tree
      Turn the current dashboard concern model into a durable parent and child
      subject hierarchy.

      [x] 69.1.1.1 Subtask - Choose terse parent-subject labels and map the
        current dashboard concerns into child subjects beneath them instead of
        keeping every concern in one first-level rail.
      [x] 69.1.1.2 Subtask - Keep the dashboard route header, signed-in
        orientation copy, settings handoff, and breadcrumb lane outside the
        selected child-subject pane.
      [x] 69.1.1.3 Subtask - Reuse any still-useful repository-monitoring ideas
        from Phases 66 and 67 as child-subject content rather than as the shell
        itself.

    [x] 69.1.2 Task - Migrate dashboard rendering to the shared shell
      Replace the current sidebar-first dashboard chrome with the accepted
      subject-tree layout while keeping route-owned feed loading and handoff
      semantics.

      [x] 69.1.2.1 Subtask - Render dashboard through the shared ordering of
        route header, breadcrumb lane, parent-subject top rail, child-subject
        sidebar, and selected-pane framing.
      [x] 69.1.2.2 Subtask - Move child-subject-local refresh, repair, or
        follow-up actions into pane-local footers instead of scattering them
        through page-global chrome.
      [x] 69.1.2.3 Subtask - Preserve direct handoff paths from dashboard child
        subjects into canonical managed-repository, governed-run, and settings
        routes.

  [x] 69.2 Section - Managed-Repo Subject-Tree Taxonomy And Migration
    Converge managed-repository detail on the same shell while preserving it as
    the canonical productive-conversation and repo-level inspection host route.

    [x] 69.2.1 Task - Establish the canonical managed-repository subject tree
      Turn the current repo-detail family set into a durable parent and child
      hierarchy that still makes conversation ownership explicit.

      [x] 69.2.1.1 Subtask - Choose terse parent-subject labels and map
        overview, conversations, semantic inspection, memory, workflows, and
        workspace-repair context into child subjects beneath them.
      [x] 69.2.1.2 Subtask - Keep repository identity, breadcrumb path, and
        route-level framing outside the selected child-subject pane so the route
        stays understandable regardless of which child subject is open.
      [x] 69.2.1.3 Subtask - Preserve the managed-repository route as the
        canonical productive-conversation host even after conversations become a
        child subject inside the newer tree.

    [x] 69.2.2 Task - Migrate repo detail rendering to the shared shell
      Replace the current primary sidebar rail with the shared subject-tree
      ordering while preserving route-owned recovery, readiness, and workflow
      behavior.

      [x] 69.2.2.1 Subtask - Render repo detail through the shared ordering of
        route header, breadcrumb lane, parent-subject top rail, child-subject
        sidebar, and selected-pane framing.
      [x] 69.2.2.2 Subtask - Move child-subject-local conversation, workflow,
        semantic, memory, and workspace-repair actions into pane-local footers
        when they are directly tied to the visible middle region.
      [x] 69.2.2.3 Subtask - Keep bounded semantic and memory widgets, degraded
        conversation continuity, and workflow readiness inside the selected pane
        rather than leaking them back into shell chrome.

  [x] 69.3 Section - Current-Truth, Helper, And Planning Convergence
    Keep implementation, route wording, and planning chronology aligned once the
    shared shell lands on both routes.

    [x] 69.3.1 Task - Reconcile route wording and helper responsibilities
      Ensure the adopted routes, helper boundaries, and historical planning
      narrative teach the same product model.

      [x] 69.3.1.1 Subtask - Update route wording, helper APIs, and test
        expectations to describe the breadcrumb plus subject-tree shell instead
        of the older sidebar-first implementations.
      [x] 69.3.1.2 Subtask - Fold any still-useful monitoring composition from
        Phases 66 and 67 into the adopted dashboard child subjects without
        keeping the obsolete shell assumptions alive.
      [x] 69.3.1.3 Subtask - Keep the planning layer explicit that Phases 61 and
        65 are historical route-owned navigation foundations while Phases 66 and
        67 are shell-level superseded steps.

  [x] 69.4 Section - Phase Integration Tests
    Prove that dashboard and managed-repository detail both honor the accepted
    shell contract across the key supported layouts and route states.

    [x] 69.4.1 Task - Add route and browser coverage for subject-tree adoption
      Verify the migrated routes at the same fidelity as the earlier dashboard
      and repo-detail shell transitions.

      [x] 69.4.1.1 Subtask - Add coverage proving both routes render breadcrumbs
        between the route header and subject navigation while keeping parent and
        child selection route-owned.
      [x] 69.4.1.2 Subtask - Add coverage proving selected child-subject panes
        keep their own `header`, `middle`, and `footer` framing instead of
        leaking pane actions into global page chrome.
      [x] 69.4.1.3 Subtask - Add browser coverage for wide and narrow layouts so
        the shared shell stays usable on both routes when breadcrumbs, parent
        subjects, and child subjects compress or restack.
