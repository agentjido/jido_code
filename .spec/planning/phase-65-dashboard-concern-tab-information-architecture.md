# Phase 65 - Dashboard Concern Tab Information Architecture

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
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md`
- `lib/jido_code/governance/runtime_evidence_feed.ex`
- `lib/jido_code/orchestration/run_summary_feed.ex`
- `lib/jido_code/workbench/dashboard_conversation_feed.ex`
- `lib/jido_code/memory_graph/dashboard_summary_feed.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/DashboardRunSummaryWidget.vue`
- `lib/jido_code_web/live/DashboardRuntimePostureWidget.vue`
- `lib/jido_code_web/components/operator_state_components.ex`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/e2e/`

## Relevant Assumptions / Defaults
- `/dashboard` is already the durable authenticated landing route for ready-state operators.
- The current dashboard cohosts recent governed runs, conversation supervision, repository memory, runtime posture, and conditional next actions as one stacked LiveView page.
- The redesign should clarify those concern families without splitting dashboard into separate routes or a client-owned application shell.
- Header framing and the settings handoff remain outside the dashboard concern tabs.
- `Next Steps` is conditional follow-up chrome, not a permanent empty-state tab in the normal ready state.

[x] 65 Phase 65 - Dashboard Concern Tab Information Architecture
  Reorganize the authenticated dashboard around route-owned concern tabs so the landing route becomes easier to scan without abandoning the current LiveView-owned shell, bounded summary widgets, or canonical repo and run handoff paths.

  [x] 65.1 Section - Canonical Concern Families And Route Ownership
    Define the dashboard concern split as a durable product contract before moving page chrome or reshaping any panels.

    [x] 65.1.1 Task - Establish the canonical dashboard concern set
      Turn the current stacked dashboard sections into a stable top-level information architecture.

      [x] 65.1.1.1 Subtask - Adopt `Overview`, `Runs`, `Conversations`, `Memory`, and `Runtime` as the default authenticated dashboard concern families.
      [x] 65.1.1.2 Subtask - Treat `Next Steps` as a conditional dashboard concern that appears only when onboarding or ready-state follow-up work exists.
      [x] 65.1.1.3 Subtask - Keep the provider-login and Git automation settings handoff in the dashboard header instead of making settings a concern tab.

    [x] 65.1.2 Task - Keep dashboard concern selection route-owned
      Preserve the dashboard as a product route rather than a client-only tab state container.

      [x] 65.1.2.1 Subtask - Represent the selected dashboard concern in LiveView-owned route state such as a query param or patchable assign so deep links and back-button behavior stay stable.
      [x] 65.1.2.2 Subtask - Keep authentication, summary-feed loading, and refresh events in the routed LiveView shell instead of moving them into a client-owned dashboard application.
      [x] 65.1.2.3 Subtask - Provide a narrow-screen dashboard concern-navigation fallback that preserves the same ordering and state semantics without depending on wide-screen tab chrome.

  [x] 65.2 Section - Tab Shell And Overview Handoff
    Add the dashboard concern navigation and the summary-first `Overview` panel in a way that improves scanability instead of duplicating the current long page behind tabs.

    [x] 65.2.1 Task - Introduce a shared dashboard concern-tab shell
      Give the route explicit concern navigation that matches the existing operator visual language.

      [x] 65.2.1.1 Subtask - Add top-of-content dashboard tabs with concise labels and selection styling that fit the current LiveView operator shell.
      [x] 65.2.1.2 Subtask - Allow dashboard tabs to expose bounded counts or warning badges such as run totals, clarification-needed conversations, stale memory summaries, or blocked runtime posture.
      [x] 65.2.1.3 Subtask - Keep the page title, signed-in orientation copy, and settings handoff visible independently of the selected tab.

    [x] 65.2.2 Task - Make `Overview` compact and summary-first
      Ensure the landing concern helps operators choose where to go next instead of becoming a duplicate dashboard.

      [x] 65.2.2.1 Subtask - Add compact overview summary cards or grouped signals for runs, conversations, memory, and runtime posture.
      [x] 65.2.2.2 Subtask - Keep overview content bounded to orientation, urgency, and handoff rather than rendering the full rows already owned by the other concern tabs.
      [x] 65.2.2.3 Subtask - Fold conditional next actions into `Overview` only when that concern does not need its own tab so empty-state chrome stays minimal.

  [x] 65.3 Section - Concern Panel Separation
    Split the current stacked dashboard sections into clearer per-concern panels while preserving their bounded product-owned projections.

    [x] 65.3.1 Task - Separate governed runs and conversation supervision
      Keep workflow activity and productive-conversation follow-up distinct so operators do not have to scan unrelated control-plane summaries together.

      [x] 65.3.1.1 Subtask - Move the recent governed-runs feed and its existing widget or fallback into `Runs`.
      [x] 65.3.1.2 Subtask - Move the bounded conversation-supervision roster into `Conversations` while preserving links back to canonical repo detail.
      [x] 65.3.1.3 Subtask - Preserve route-local refresh and stale-state messaging for each concern without forcing a global dashboard reload.

    [x] 65.3.2 Task - Separate memory and runtime posture into their own concern panels
      Keep graph-backed follow-up and runtime-governance posture legible as distinct dashboard concern families.

      [x] 65.3.2.1 Subtask - Move repository-memory and workflow-provenance summaries into `Memory` while keeping them bounded and action-oriented.
      [x] 65.3.2.2 Subtask - Move runtime posture and degraded-path summaries into `Runtime` while preserving product-oriented wording and governed-record handoff.
      [x] 65.3.2.3 Subtask - Keep `Next Steps` conditional and explicitly separated from the always-on concern families when it appears as its own tab.

  [x] 65.4 Section - Current-Truth And Helper Convergence
    Align helpers, widgets, and current-truth language once the dashboard concern split is real so the implementation and specs teach the same product model.

    [x] 65.4.1 Task - Reconcile dashboard helpers and specs with the concern-tab model
      Keep the dashboard cutover explicit in both code boundaries and current-truth subjects.

      [x] 65.4.1.1 Subtask - Update dashboard helper boundaries and any bounded widgets so their responsibilities map cleanly to `Overview`, `Runs`, `Conversations`, `Memory`, `Runtime`, and conditional `Next Steps`.
      [x] 65.4.1.2 Subtask - Update baseline, factory-control-plane, frontend, repo-posture, conversation, memory, and runtime current-truth subjects to describe the route-owned dashboard concern model once implemented.
      [x] 65.4.1.3 Subtask - Retire stale stacked-dashboard copy that implies the dashboard is only a vertically growing summary page rather than a durable authenticated landing with explicit concern navigation.

  [x] 65.5 Section - Phase Integration Tests
    Prove the dashboard concern split improves navigation and clarity without breaking route ownership, bounded summary behavior, or ready-state landing expectations.

    [x] 65.5.1 Task - Add dashboard route and browser coverage for concern navigation
      Verify the dashboard tabs and their most important concern states as an operator would actually use them.

      [x] 65.5.1.1 Subtask - Add LiveView coverage proving `Overview`, `Runs`, `Conversations`, `Memory`, and `Runtime` expose the intended concern family and do not leak the full neighboring concern panels by default.
      [x] 65.5.1.2 Subtask - Add coverage proving conditional `Next Steps` behavior only renders its tab or overview summary when follow-up actions exist.
      [x] 65.5.1.3 Subtask - Add browser coverage for wide-screen tab behavior and narrow-screen fallback navigation so the authenticated landing remains usable across supported viewports.
