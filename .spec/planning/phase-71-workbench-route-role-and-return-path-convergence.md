# Phase 71 - Workbench Route Role And Return-Path Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.operator_surface_information_architecture.workbench_route_is_specialist_dense_mode -->
<!-- covers: baseline.surface.dashboard_remains_ready_state_authenticated_landing -->
<!-- covers: architecture.factory_control_plane.dashboard_work_subject_owns_primary_repo_inventory -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/operator_surface_information_architecture.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../decisions/jido_code.post_onboarding_subject_tree_operator_shell.md`
- `../planning/phase-70-dashboard-work-subject-and-workbench-content-convergence.md`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `test/e2e/dashboard-tabs.spec.ts`
- `test/e2e/conversation-ui.spec.ts`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 70 has already moved the primary managed-repository inventory and triage
  story under dashboard `Work`.
- `/workbench` may still survive as a dense specialist route, a product-owned
  alias, or a redirect, but it should no longer behave like a competing default
  parent context for repo-detail navigation.
- Repo detail and related follow-up routes still carry historical `return_to`
  seams that can fall back toward Workbench semantics when no explicit parent
  route is preserved.
- Dashboard, repo detail, and Workbench should all keep using product-owned
  managed-repository and governed-run records rather than inventing route-local
  state to repair navigation.

[ ] 71 Phase 71 - Workbench Route Role And Return-Path Convergence
  Clean up route semantics once dashboard owns primary repo inventory so
  dashboard-originated flows preserve their real parent context and `/workbench`
  settles into a bounded dense specialist mode, alias, or redirect.

  [ ] 71.1 Section - Parent-Context And Return-Path Cleanup
    Remove the residual navigation seams that still imply Workbench is the
    default signed-in parent surface when the real origin is dashboard.

    [ ] 71.1.1 Task - Normalize repo-detail parent context
      Make repo detail, child surfaces, and follow-up routes preserve their real
      parent route instead of falling back silently to Workbench semantics.

      [ ] 71.1.1.1 Subtask - Ensure dashboard-originated repo-detail links
        preserve dashboard `Work` as the parent context rather than inheriting a
        default Workbench return path when no explicit value is passed.
      [ ] 71.1.1.2 Subtask - Keep explicit Workbench-originated flows returning
        to Workbench only when the operator actually came from the dense
        specialist route.
      [ ] 71.1.1.3 Subtask - Align breadcrumb and back-label wording with the
        actual parent route so repo detail no longer hints that Workbench is the
        canonical signed-in home.

    [ ] 71.1.2 Task - Normalize specialist follow-up routes
      Keep route-owned navigation legible when operators move among dashboard,
      Workbench, repo detail, and governed-run follow-up surfaces.

      [ ] 71.1.2.1 Subtask - Preserve actual parent context through
        conversation, memory, semantic, workflow, and governed-run handoff links
        instead of hard-coding one historical parent route.
      [ ] 71.1.2.2 Subtask - Keep direct URL entry resilient by choosing a
        sensible product-owned fallback that matches the newer dashboard-first
        product model.
      [ ] 71.1.2.3 Subtask - Avoid client-only navigation memory so route state
        stays testable and reproducible.

  [ ] 71.2 Section - Final Workbench Route Role
    Decide and implement the enduring role of `/workbench` after dashboard owns
    the primary managed-repository inventory experience.

    [ ] 71.2.1 Task - Choose the stable route behavior
      Settle whether Workbench remains a dense specialist surface, becomes a
      product-owned alias, or redirects into the canonical dashboard `Work`
      subject.

      [ ] 71.2.1.1 Subtask - If Workbench remains a route, keep it clearly
        bounded as a denser specialist mode with shared dashboard content and no
        separate top-level taxonomy.
      [ ] 71.2.1.2 Subtask - If Workbench becomes an alias or redirect, ensure
        the destination preserves the canonical dashboard subject and child
        selection rather than dropping operators at a generic landing page.
      [ ] 71.2.1.3 Subtask - Update auth, welcome, and product copy so no
        ready-state path or route hint implies Workbench is the main signed-in
        landing surface.

    [ ] 71.2.2 Task - Retire unnecessary duplicated surface logic
      Reduce the number of route-specific seams once the Workbench role is
      explicit.

      [ ] 71.2.2.1 Subtask - Remove or simplify duplicate helper paths that
        exist only to compensate for the older Workbench-first assumptions.
      [ ] 71.2.2.2 Subtask - Keep any remaining dense-mode distinctions confined
        to presentation and operator density rather than route-owned business
        rules.
      [ ] 71.2.2.3 Subtask - Keep tests and contributor guidance explicit about
        the final relationship between dashboard `Work`, repo detail, and
        Workbench.

  [ ] 71.3 Section - Phase Integration Tests
    Prove that the final Workbench role and repo-detail return paths match the
    dashboard-first signed-in model.

    [ ] 71.3.1 Task - Add route and browser coverage for parent-context cleanup
      Verify the final role at the same fidelity as the earlier shell and
      dashboard/workbench convergence work.

      [ ] 71.3.1.1 Subtask - Add route coverage proving dashboard-originated
        repo-detail links preserve dashboard `Work` context instead of silently
        falling back to Workbench.
      [ ] 71.3.1.2 Subtask - Add coverage proving explicit Workbench-originated
        specialist flows still round-trip correctly when Workbench is retained
        as a dense mode or alias.
      [ ] 71.3.1.3 Subtask - Add browser coverage proving breadcrumb, back-path,
        and direct-entry behavior stay coherent across dashboard, repo detail,
        Workbench, and governed-run follow-up routes.
