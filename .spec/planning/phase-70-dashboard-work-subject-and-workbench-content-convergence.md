# Phase 70 - Dashboard Work Subject And Workbench Content Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.operator_surface_information_architecture.dashboard_work_subject_hosts_primary_repo_inventory -->
<!-- covers: architecture.operator_surface_information_architecture.workbench_route_is_specialist_dense_mode -->
<!-- covers: architecture.factory_control_plane.dashboard_work_subject_owns_primary_repo_inventory -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/operator_surface_information_architecture.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../decisions/jido_code.post_onboarding_subject_tree_operator_shell.md`
- `../planning/phase-69-dashboard-and-managed-repo-subject-tree-adoption.md`
- `lib/jido_code/workbench/inventory.ex`
- `lib/jido_code/workbench/dashboard_repository_monitoring_feed.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `test/e2e/dashboard-tabs.spec.ts`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 69 has already landed the shared subject-tree shell on dashboard and
  managed-repository detail.
- The dashboard top rail should stay semantic and product-oriented, so
  `Workbench` should not become a peer top-level subject beside `Work`,
  `Knowledge`, and `Runtime`.
- `/workbench` still contains the densest managed-repository inventory and issue
  plus pull-request triage experience, even though dashboard is now the durable
  ready-state landing route.
- The next convergence should reuse product-owned inventory, filter, and triage
  boundaries instead of creating one more dashboard-only repository list model.

[ ] 70 Phase 70 - Dashboard Work Subject And Workbench Content Convergence
  Move the strongest managed-repository inventory and triage patterns under the
  dashboard `Work` subject so dashboard becomes the primary signed-in home for
  repository-first scanning while `/workbench` stops teaching a separate
  top-level mental model.

  [ ] 70.1 Section - Canonical Dashboard Work Content Model
    Decide how dashboard `Work` absorbs the best repository-inventory and triage
    behavior without collapsing back into a route-global tool taxonomy.

    [ ] 70.1.1 Task - Define the canonical dashboard `Work` child-subject shape
      Choose the child-subject structure and naming that will own primary
      repository inventory and triage on the signed-in landing route.

      [ ] 70.1.1.1 Subtask - Decide whether the canonical dense inventory lives
        under `Work > Overview`, `Work > Inventory`, or another terse child
        subject without making `Workbench` itself a top-level subject.
      [ ] 70.1.1.2 Subtask - Preserve repository-first monitoring, issue and
        pull-request triage, freshness, and recent-work ordering as one coherent
        product story instead of splitting them between dashboard and Workbench
        arbitrarily.
      [ ] 70.1.1.3 Subtask - Keep the dashboard landing experience lighter and
        more immediately scannable than the full specialist route even when it
        inherits the same domain model.

    [ ] 70.1.2 Task - Define shared content and helper boundaries
      Converge dashboard and Workbench on one reusable inventory and triage
      content model rather than continuing to maintain two unrelated surfaces.

      [ ] 70.1.2.1 Subtask - Reuse product-owned inventory loading, filter
        shaping, and repo-detail handoff helpers instead of duplicating them in
        dashboard-only code.
      [ ] 70.1.2.2 Subtask - Split compact-versus-dense presentation concerns
        from the underlying managed-repository inventory and triage data model
        so dashboard and Workbench can share content without becoming visually
        identical.
      [ ] 70.1.2.3 Subtask - Keep settings, governed-run, and repo-detail
        follow-up paths product-owned and understandable from either surface.

  [ ] 70.2 Section - Dashboard Work Implementation
    Apply the chosen content model to dashboard `Work` so the signed-in landing
    route becomes the primary operator home for repository inventory and triage.

    [ ] 70.2.1 Task - Implement the converged dashboard inventory surface
      Replace or extend the current lighter repository-monitoring pane with the
      shared Workbench-derived inventory and triage model.

      [ ] 70.2.1.1 Subtask - Render the selected dashboard `Work` child subject
        through the shared subject pane while hosting repository cards, compact
        table cues, or equivalent dense inventory scanning content there.
      [ ] 70.2.1.2 Subtask - Preserve product-owned issue and pull-request
        triage actions, recent-run links, memory and runtime cues, and bounded
        recovery affordances within the dashboard surface.
      [ ] 70.2.1.3 Subtask - Keep the dashboard `Work` pane usable on narrower
        screens without dropping the shell hierarchy or forcing operators back
        into Workbench for normal product flow.

    [ ] 70.2.2 Task - Keep Workbench aligned during the transition
      Allow Workbench to remain available while dashboard takes over the primary
      inventory role.

      [ ] 70.2.2.1 Subtask - Reuse shared widgets, row rendering, or supporting
        helpers so Workbench and dashboard no longer drift in repository meaning
        or follow-up actions.
      [ ] 70.2.2.2 Subtask - Update surface copy so Workbench reads as a denser
        specialist mode rather than the main signed-in entry route.
      [ ] 70.2.2.3 Subtask - Keep repo-detail links and specialist launch paths
        coherent while both routes coexist.

  [ ] 70.3 Section - Current-Truth And Contributor Convergence
    Keep the specs, helper seams, and operator-facing language aligned once
    dashboard `Work` becomes the primary inventory home.

    [ ] 70.3.1 Task - Reconcile route wording and product guidance
      Teach one consistent relationship between dashboard `Work` and Workbench.

      [ ] 70.3.1.1 Subtask - Update current-truth route wording so dashboard is
        the canonical signed-in landing and Workbench is described only as a
        dense specialist mode or alias.
      [ ] 70.3.1.2 Subtask - Retire stale wording that still frames dashboard
        overview as lighter summary-only monitoring or Workbench as the primary
        managed-repository inventory surface.
      [ ] 70.3.1.3 Subtask - Keep planning explicit that the top-level shell is
        already landed and this phase is about content convergence, not a new
        taxonomy rewrite.

  [ ] 70.4 Section - Phase Integration Tests
    Prove that dashboard now owns the primary managed-repository inventory story
    without regressing Workbench or the shared subject-tree shell.

    [ ] 70.4.1 Task - Add route and browser coverage for converged inventory
      Verify the dashboard `Work` adoption at the same fidelity as the earlier
      shell rollout.

      [ ] 70.4.1.1 Subtask - Add dashboard route coverage proving repository
        inventory and triage now live under the `Work` subject instead of being
        modeled as a separate top-level Workbench taxonomy.
      [ ] 70.4.1.2 Subtask - Add coverage proving dashboard and Workbench share
        consistent repo-detail, run-detail, settings, and repair follow-up
        paths even when their density differs.
      [ ] 70.4.1.3 Subtask - Add browser coverage for wide and narrow layouts
        so the converged dashboard `Work` pane remains usable without requiring
        Workbench for ordinary signed-in navigation.
