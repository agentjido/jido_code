# Phase 14 - Incremental Operator Surface Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/frontend_architecture.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../specs/repo_posture.spec.md`
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/settings_live.ex`

## Relevant Assumptions / Defaults
- Phases 12 and 13 have established the frontend toolchain, host-shell integration, mounting conventions, and hybrid test strategy.
- The product should adopt `live_vue` incrementally, starting with the highest-value operator surfaces rather than trying to convert every route at once.
- Simpler routes may remain plain LiveView where richer client composition is not justified.

[ ] 14 Phase 14 - Incremental Operator Surface Adoption
  Migrate the highest-value operator-facing surfaces onto the new LiveView-plus-`live_vue` composition model in a controlled sequence that improves interactivity without destabilizing the product shell.

  [x] 14.1 Section - Dashboard and Summary Surface Adoption
    Start with summary-heavy operator surfaces where richer client composition can improve clarity, filtering, and progressive disclosure without owning the route lifecycle.

    [x] 14.1.1 Task - Migrate dashboard summary widgets to Live Vue-backed components
      Use Vue-backed components where richer visual grouping, filtering, or incremental disclosure benefits operator understanding.

      [x] 14.1.1.1 Subtask - Identify dashboard panels or widgets that benefit most from richer client composition.
      [x] 14.1.1.2 Subtask - Keep the dashboard route and data ownership in LiveView while mounting bounded Vue-backed components for the richer regions.
      [x] 14.1.1.3 Subtask - Preserve product-oriented runtime posture and governed evidence language in the migrated widgets.

    [x] 14.1.2 Task - Migrate one additional summary-oriented operator surface
      Prove the pattern can generalize beyond the dashboard before deeper workflow screens are converted.

      [x] 14.1.2.1 Subtask - Choose a second summary-heavy route such as repo inventory, workbench summary regions, or settings overview.
      [x] 14.1.2.2 Subtask - Apply the same bounded mounting and event conventions introduced in Phase 13.
      [x] 14.1.2.3 Subtask - Keep route-level auth, policy gating, and server-authored loading logic fully in LiveView.

  [ ] 14.2 Section - Deep Workflow Surface Adoption
    Migrate the richer workflow-heavy pages after the summary surfaces prove the hybrid pattern is operationally safe.

    [ ] 14.2.1 Task - Introduce Live Vue-backed components on project and run detail surfaces
      Improve highly interactive operator workflows while preserving the server-owned product shell and runtime-governance integrations.

      [ ] 14.2.1.1 Subtask - Migrate the highest-value project-detail subregions to Vue-backed components while keeping conversation, run, and policy ownership on the server side.
      [ ] 14.2.1.2 Subtask - Migrate the most interaction-heavy run-detail regions where richer client composition improves evidence navigation or review handling.
      [ ] 14.2.1.3 Subtask - Preserve typed runtime evidence, operator review, and control-plane state transitions through the existing product boundaries.

    [ ] 14.2.2 Task - Adopt Live Vue selectively on workbench-style surfaces
      Use the new browser stack where composability helps the most, without forcing every workbench interaction into the richer client path.

      [ ] 14.2.2.1 Subtask - Identify workbench regions that need richer progressive disclosure, layout composition, or client-local interaction.
      [ ] 14.2.2.2 Subtask - Keep streaming, runtime-delivery, and product event translation on the LiveView side unless a richer client component truly needs a bounded projection.
      [ ] 14.2.2.3 Subtask - Preserve compatibility for routes or sections that should remain plain HEEx and LiveView.

  [ ] 14.3 Section - Phase 14 Integration Tests
    Validate the surface-by-surface migration pattern so later rollout hardening can focus on resilience rather than basic composition correctness.

    [ ] 14.3.1 Task - Summary-surface migration scenarios
      Verify the first hybrid operator screens improve composition without changing route or auth ownership.

      [ ] 14.3.1.1 Subtask - Add coverage for a dashboard or summary page rendering Vue-backed components inside a LiveView-owned route.
      [ ] 14.3.1.2 Subtask - Add coverage for operator interaction flowing from Vue back into LiveView-driven state updates.
      [ ] 14.3.1.3 Subtask - Add coverage showing plain LiveView fallback regions remain functional on the same page.

    [ ] 14.3.2 Task - Workflow-surface migration scenarios
      Verify deeper operator workflows still preserve product-owned state transitions and governed runtime integrations after adopting richer client components.

      [ ] 14.3.2.1 Subtask - Add coverage for project- or run-detail hybrid interactions.
      [ ] 14.3.2.2 Subtask - Add coverage for runtime evidence or review flows traversing Vue-backed regions without leaking runtime-native transport details.
      [ ] 14.3.2.3 Subtask - Verify planning, specs, and surface-level tests stay aligned through the incremental migration.
