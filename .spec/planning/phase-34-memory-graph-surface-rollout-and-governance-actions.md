# Phase 34 - Memory Graph Surface Rollout And Governance Actions

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/memory_graph_surface_rollout_and_governance_actions.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/repo_posture.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `../decisions/jido_code.memory_graph_surface_rollout_and_governance_actions.md`
- `lib/jido_code/memory_graph/`
- `lib/jido_code/workbench/`
- `lib/jido_code/governance/`
- `lib/jido_code/orchestration/`
- `lib/jido_code_web/live/`
- `lib/jido_code_web/components/`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 32 and 33 established repository-detail memory inspection, governed run-detail memory context, product-owned operator memory actions, and explicit workflow retrieval policies.
- The next step is rollout breadth: bounded memory behavior should become available on the remaining canonical governed and operator surfaces rather than staying concentrated in a few routes.
- Memory context and operator actions must continue to route through product-owned services and capture-plane updates instead of direct graph writes or surface-local special cases.

[ ] 34 Phase 34 - Memory Graph Surface Rollout And Governance Actions
  Roll out bounded memory context, operator memory actions, and consistent cross-graph navigation across the remaining canonical dashboard and governed product surfaces.

  [ ] 34.1 Section - Dashboard And Governed Surface Memory Rollout
    Expand bounded memory and workflow-provenance context into dashboard summaries and the remaining governed surfaces beyond run detail.

    [ ] 34.1.1 Task - Add dashboard memory and provenance summary boundaries
      Establish the product-owned summary and view-model boundaries that let dashboard present action-oriented memory state without becoming a graph browser.

      [ ] 34.1.1.1 Subtask - Add product-owned dashboard summary loaders for repository memory freshness, invalidation, recovery, and follow-up signals.
      [ ] 34.1.1.2 Subtask - Keep dashboard summaries bounded, repository-scoped, and linked back to canonical product routes instead of graph-only views.
      [ ] 34.1.1.3 Subtask - Preserve product-oriented feedback language for stale, invalidated, recovery-required, and action-needed memory states.

    [ ] 34.1.2 Task - Add memory context to remaining governed surfaces
      Extend the bounded memory context model from run detail into work-item, evidence, and decision surfaces.

      [ ] 34.1.2.1 Subtask - Add product-owned loaders and view models for work-item memory and provenance context.
      [ ] 34.1.2.2 Subtask - Add bounded memory context shaping for evidence and decision surfaces.
      [ ] 34.1.2.3 Subtask - Keep all surfaces canonical governed routes instead of introducing graph-first alternatives.

  [ ] 34.2 Section - Operator Memory Actions Across Canonical Surfaces
    Make the existing product-owned memory action boundary available from the remaining canonical surfaces that host memory context.

    [ ] 34.2.1 Task - Reuse bounded memory actions across dashboard and governed views
      Let operators validate, invalidate, supersede, and promote memory from the surfaces where they already see the relevant governed context.

      [ ] 34.2.1.1 Subtask - Expose validate and invalidate actions through dashboard-linked and governed-surface affordances without changing the underlying operator service contract.
      [ ] 34.2.1.2 Subtask - Expose supersede and promote actions from work-item, evidence, and decision views when those records host bounded memory context.
      [ ] 34.2.1.3 Subtask - Keep all mutations flowing through product-owned action boundaries and capture-plane updates instead of surface-local mutation helpers.

    [ ] 34.2.2 Task - Preserve explainable follow-up and mutation feedback across surfaces
      Ensure operators can understand what changed and what follow-up was created no matter which canonical surface originated the action.

      [ ] 34.2.2.1 Subtask - Standardize action feedback, supersession context, and follow-up outcome shaping across dashboard and governed surfaces.
      [ ] 34.2.2.2 Subtask - Preserve freshness, revision, provenance, and supersession metadata in the surface-level feedback contracts.
      [ ] 34.2.2.3 Subtask - Keep memory-driven follow-up re-entering governed product records rather than remaining graph-local state.

  [ ] 34.3 Section - Cross-Graph Navigation And Memory-Aware Product Flows
    Standardize how operators move among memory, provenance, source code, and governed history, and align memory-aware workflow and follow-up surfaces with that same product-owned contract.

    [ ] 34.3.1 Task - Standardize cross-graph navigation across dashboard and governed surfaces
      Make navigation among memory, provenance, code anchors, and governed records consistent across the canonical product routes that host memory context.

      [ ] 34.3.1.1 Subtask - Add shared navigation shaping for dashboard summaries, work items, evidence, and decisions.
      [ ] 34.3.1.2 Subtask - Keep navigation repository-scoped, bounded, and explainable when memory or source-code graphs are stale or recovering.
      [ ] 34.3.1.3 Subtask - Avoid exposing raw graph identifiers or surface-specific route contracts as the UI boundary.

    [ ] 34.3.2 Task - Align memory-aware workflow and governed follow-up surfaces
      Ensure memory-aware suggestions and follow-up preparation on product surfaces consume the same bounded product projections already used by services.

      [ ] 34.3.2.1 Subtask - Add bounded memory-aware suggestion or follow-up context shaping for the governed surfaces that stage operator action.
      [ ] 34.3.2.2 Subtask - Keep planner, reviewer, explainer, and governed follow-up paths consuming product-shaped memory projections instead of raw graph responses.
      [ ] 34.3.2.3 Subtask - Preserve explainable links among surface context, workflow retrieval intent, and resulting governed follow-up.

  [ ] 34.4 Section - Phase 34 Integration Tests
    Verify that memory rollout, operator actions, and cross-graph navigation remain bounded, explainable, and canonical across dashboard and the remaining governed surfaces.

    [ ] 34.4.1 Task - Dashboard and governed surface rollout scenarios
      Prove the new surfaces can host bounded memory context safely and consistently.

      [ ] 34.4.1.1 Subtask - Add coverage proving dashboard summaries expose bounded memory freshness and action-needed state without becoming graph browsers.
      [ ] 34.4.1.2 Subtask - Add coverage proving work-item, evidence, and decision surfaces can host bounded memory and provenance context through product-owned loaders.
      [ ] 34.4.1.3 Subtask - Add coverage proving cross-graph navigation stays repository-scoped and consistent across the expanded surfaces.

    [ ] 34.4.2 Task - Operator action and memory-aware follow-up scenarios
      Prove canonical surface actions and follow-up preparation remain governed and product-owned.

      [ ] 34.4.2.1 Subtask - Add coverage proving validate, invalidate, supersede, and promote actions remain available through canonical surface affordances and still flow through bounded product action boundaries.
      [ ] 34.4.2.2 Subtask - Add coverage proving memory-aware workflow and governed follow-up surfaces consume product-shaped memory projections instead of raw graph responses.
      [ ] 34.4.2.3 Subtask - Verify the spec workspace remains coherent after Phase 34 expands memory rollout across dashboard and governed surfaces.
