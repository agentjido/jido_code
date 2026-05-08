# Phase 67 - Dashboard Repository Panels And Accordion Monitoring

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->
<!-- covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state -->
<!-- covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented -->
<!-- covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Status Note
- This phase remains a historical dashboard refinement step that captured useful
  repository-monitoring composition ideas.
- Its shell-level target is superseded by
  `jido_code.post_onboarding_subject_tree_operator_shell` and
  `architecture.operator_surface_information_architecture`.
- Forward implementation work should now reuse only the still-useful monitoring
  content ideas inside the newer shared subject-tree shell rather than reviving
  the older left-sidebar-first dashboard shell.

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
- `../planning/phase-66-dashboard-sidebar-and-repository-monitoring-foundation.md`
- `lib/jido_code/governance/runtime_evidence_feed.ex`
- `lib/jido_code/orchestration/run_summary_feed.ex`
- `lib/jido_code/workbench/dashboard_conversation_feed.ex`
- `lib/jido_code/memory_graph/dashboard_summary_feed.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/components/operator_state_components.ex`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/e2e/dashboard-tabs.spec.ts`

## Relevant Assumptions / Defaults
- Phase 66 is the immediate foundation for this phase and should already have landed the left-sidebar shell plus repository-first overview ordering.
- Each overview entry should remain a bounded monitoring surface, not a hidden second repo-detail route.
- The refined ADR now expects a simple repository monitoring card that keeps summary content first and bounded inline detail below it.
- Inline detail should keep operators oriented toward canonical managed-repository, run, and settings routes rather than duplicating those routes wholesale inside dashboard.
- Other dashboard concerns continue to exist, but `Overview` becomes the primary monitoring workspace for multi-project supervision.

[x] 67 Phase 67 - Dashboard Repository Panels And Accordion Monitoring
  Turn the repository-first overview scaffold into the final developer-centric monitoring surface by adopting the simple repository monitoring card, bounded inline detail, and the supporting helper plus verification convergence.

  [x] 67.1 Section - Repository Card Composition
    Implement the core overview entry layout so each repository becomes a legible monitoring card rather than a generic list row or faux split panel.

    [x] 67.1.1 Task - Render each repository overview entry as a simple monitoring card
      Give the overview list the card-based visual structure defined by the refined ADR.

      [x] 67.1.1.1 Subtask - Replace any interim repository row or faux split-panel styling with a simple monitoring card.
      [x] 67.1.1.2 Subtask - Keep repository context first and the bounded detail region below it inside the same card.
      [x] 67.1.1.3 Subtask - Keep the layout responsive so the monitoring card remains usable on narrower screens without losing the repository-first hierarchy.

    [x] 67.1.2 Task - Make the upper summary region developer-centric
      Ensure the first visible portion of each repository card tells an operator why that repository currently matters.

      [x] 67.1.2.1 Subtask - Surface repository identity, latest meaningful activity timing, and the highest-signal current work cue in the summary region.
      [x] 67.1.2.2 Subtask - Include bounded attention badges or status cues such as active conversations, run pressure, memory warnings, or runtime blockers without overwhelming the card.
      [x] 67.1.2.3 Subtask - Preserve direct handoff affordances from the top card back to canonical managed-repository routes.

  [x] 67.2 Section - Inline Detail And Bounded Concern Handoff
    Use the lower portion of each repository card to reveal more detail in place while preserving dashboard’s role as a monitoring surface instead of a second primary workspace.

    [x] 67.2.1 Task - Add bounded per-repository inline detail
      Make the lower detail region useful enough for triage without collapsing the rest of the product into dashboard.

      [x] 67.2.1.1 Subtask - Populate the detail region with bounded detail such as latest governed run state, active conversation posture, memory attention cues, runtime warnings, or recent follow-up signals.
      [x] 67.2.1.2 Subtask - Keep each detail section product-shaped and monitoring-oriented rather than exposing raw graph, transcript, or transport internals.
      [x] 67.2.1.3 Subtask - Preserve explicit handoff links from inline detail into canonical repo detail, governed run detail, or settings routes where deeper action belongs.

    [x] 67.2.2 Task - Keep inline detail lightweight and route-compatible
      Ensure the repository detail remains a bounded LiveView presentation instead of creating a second navigation model.

      [x] 67.2.2.1 Subtask - Keep the inline detail inside the LiveView-owned dashboard shell rather than moving it into a separate client-owned monitoring application.
      [x] 67.2.2.2 Subtask - Add clear empty-state behavior so repositories without recent governed activity still render legibly.
      [x] 67.2.2.3 Subtask - Preserve scanability across many repositories so showing detail does not destabilize ordering or context for the rest of the list.

  [x] 67.3 Section - Current-Truth And Helper Convergence
    Align helper boundaries, product wording, and durable current-truth language once the final repository monitoring composition is real.

    [x] 67.3.1 Task - Reconcile overview helper boundaries and dashboard language with the monitoring-card model
      Keep the shipped implementation and the accepted ADR teaching the same dashboard concept.

      [x] 67.3.1.1 Subtask - Update dashboard helper or feed responsibilities so repository monitoring ordering, summary-card data, and inline detail stay cleanly separated.
      [x] 67.3.1.2 Subtask - Update the affected dashboard, frontend, factory-control-plane, repo-posture, conversation, memory, and runtime current-truth subjects once the repository-card model is implemented.
      [x] 67.3.1.3 Subtask - Retire stale dashboard copy that still frames overview as summary-first or concern-first instead of repository-first monitoring.

  [x] 67.4 Section - Phase Integration Tests
    Prove the final repository monitoring composition works as an operator-facing dashboard surface across the key supported layouts.

    [x] 67.4.1 Task - Add route and browser coverage for the repository monitoring cards and inline detail behavior
      Verify the new overview model at the same level of fidelity as the earlier dashboard navigation cutover.

      [x] 67.4.1.1 Subtask - Add LiveView coverage proving each overview repository entry renders as a simple monitoring card with a summary region and a lower detail region.
      [x] 67.4.1.2 Subtask - Add LiveView coverage proving inline detail preserves direct handoff links to canonical routes.
      [x] 67.4.1.3 Subtask - Add browser coverage for desktop sidebar plus inline detail behavior and narrow-screen repository monitoring fallback so the dashboard remains usable across supported viewports.
