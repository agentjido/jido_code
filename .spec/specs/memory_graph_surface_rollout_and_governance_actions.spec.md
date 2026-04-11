# Memory Graph Surface Rollout And Governance Actions

This subject defines how bounded memory and workflow-provenance adoption should
roll out across the remaining canonical operator and governed product surfaces.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.memory_graph_surface_rollout_and_governance_actions
kind: feature
status: proposed
summary: Jido.Code expands memory-graph product adoption beyond repository detail and run detail into dashboard summaries plus canonical work-item, evidence, and decision surfaces, uses product-owned services and view-model boundaries to host bounded memory and workflow-provenance context on those routes, makes validate, invalidate, supersede, and promote actions available from those same canonical surfaces rather than through special-case graph views, keeps memory-aware summaries and follow-up suggestions bounded and action-oriented, standardizes cross-graph navigation among memory, provenance, source code, and governed records across the remaining operator surfaces, and ensures memory-aware workflow or governed follow-up continues to consume product-shaped projections instead of raw graph responses, with dashboard summary feeds, governed surface sections, follow-up preview widgets, and the new typed governed-reference contract all staying tied to canonical product routes.
decisions:
  - jido_code.memory_graph_product_adoption
  - jido_code.memory_graph_workflow_and_operator_expansion
  - jido_code.memory_graph_surface_rollout_and_governance_actions
surface:
  - .spec/decisions/jido_code.memory_graph_surface_rollout_and_governance_actions.md
  - .spec/specs/memory_graph_product_adoption.spec.md
  - .spec/specs/memory_graph_workflow_and_operator_expansion.spec.md
  - .spec/planning/phase-34-memory-graph-surface-rollout-and-governance-actions.md
  - lib/jido_code/memory_graph/
  - lib/jido_code/workbench/
  - lib/jido_code/governance/
  - lib/jido_code_web/live/
  - lib/jido_code_web/components/
  - test/jido_code/
  - test/jido_code_web/live/
```

## Requirements

```spec-requirements
- id: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
  statement: Dashboard summaries plus canonical work-item, evidence, and decision surfaces may host bounded memory and workflow-provenance context when that context explains governed state, freshness, review pressure, or follow-up needs, but they shall remain product and governed surfaces rather than graph-only views.
  priority: must
  stability: proposed

- id: architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
  statement: Product-owned validate, invalidate, supersede, and promote memory actions shall be available from canonical governed and operator surfaces that already host bounded memory context instead of being confined to special-case semantic views.
  priority: must
  stability: proposed

- id: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
  statement: Dashboard memory and provenance summaries shall present bounded freshness, stale, invalidated, recovery, and follow-up signals that help operators choose action without exposing raw graph queries, low-level RDF details, or route-breaking graph browser state.
  priority: should
  stability: proposed

- id: architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces
  statement: Cross-graph navigation among memory, workflow provenance, source-code anchors, runs, work items, evidence, and decisions shall remain repository-scoped and product-shaped across dashboard, managed-repository, and governed surfaces instead of varying by surface-specific graph contracts.
  priority: should
  stability: proposed

- id: architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
  statement: Memory-aware workflow preparation, operator follow-up, and governed action suggestions shown on product surfaces shall consume bounded product projections, summaries, or view models instead of raw graph responses or direct pod interactions.
  priority: must
  stability: proposed

- id: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  statement: Dashboard, managed-repository, run, work-item, evidence, and decision routes shall remain the canonical product-owned surfaces for memory-backed operator behavior, and the architecture shall not introduce a separate graph-first route family as the main operator contract.
  priority: must
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.memory_graph_surface_rollout_and_governance_actions.scenario_dashboard_summarizes_memory_state
  covers:
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
    - architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  given:
    - A managed repository has fresh, stale, invalidated, or recovery-required memory state plus recent governed follow-up pressure.
  when:
    - An operator opens dashboard or an adjacent summary surface.
  then:
    - The dashboard shows bounded memory status and action-needed signals.
    - The operator can navigate into canonical product routes for deeper governed context.
    - The dashboard does not become a raw graph inspection surface.

- id: architecture.memory_graph_surface_rollout_and_governance_actions.scenario_governed_surfaces_offer_memory_actions
  covers:
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
    - architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  given:
    - A work-item, evidence, or decision surface hosts bounded durable memory context.
  when:
    - An operator validates, invalidates, supersedes, or promotes one of those memories.
  then:
    - The action flows through product-owned services and capture-plane updates.
    - The surface remains a canonical governed view instead of mutating the graph directly.

- id: architecture.memory_graph_surface_rollout_and_governance_actions.scenario_cross_graph_navigation_is_consistent
  covers:
    - architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  given:
    - A memory, provenance record, or governed record links to related source code and other governed history.
  when:
    - An operator follows those relationships from different canonical surfaces.
  then:
    - Navigation remains repository-scoped and bounded.
    - The product presents stable cross-graph movement without exposing graph-specific route contracts.

- id: architecture.memory_graph_surface_rollout_and_governance_actions.scenario_memory_aware_follow_up_stays_product_shaped
  covers:
    - architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
    - architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
  given:
    - A governed or workflow surface wants to suggest, stage, or perform follow-up work informed by durable memory.
  when:
    - The product prepares that action or suggestion.
  then:
    - The surface uses bounded product projections and view models.
    - The resulting follow-up continues to re-enter canonical governed records.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_surface_rollout_and_governance_actions.md
  covers:
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
    - architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
    - architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
    - architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed

- kind: source_file
  target: .spec/specs/memory_graph_surface_rollout_and_governance_actions.spec.md
  covers:
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
    - architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
    - architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
    - architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed

- kind: source_file
  target: .spec/planning/phase-34-memory-graph-surface-rollout-and-governance-actions.md
  covers:
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
    - architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
    - architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces
    - architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
    - architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed

```
