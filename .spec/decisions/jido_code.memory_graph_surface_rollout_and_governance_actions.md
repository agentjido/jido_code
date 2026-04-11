---
id: jido_code.memory_graph_surface_rollout_and_governance_actions
status: accepted
date: 2026-04-11
affects:
  - architecture.factory_control_plane
  - architecture.frontend_stack
  - architecture.memory_graph_product_adoption
  - architecture.memory_graph_surface_rollout_and_governance_actions
  - package.jido_code
related:
  - jido_code.memory_graph_product_adoption
  - jido_code.memory_graph_workflow_and_operator_expansion
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
  - jido_code.source_code_graph_product_adoption
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane -->
<!-- covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions -->
<!-- covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary -->
<!-- covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed -->

# Memory Graph Surface Rollout And Governance Actions

## Context

Phases 32 and 33 established a real product-owned memory capability:

- managed-repository surfaces can inspect durable memory and workflow
  provenance through bounded product services
- governed run detail can host bounded memory context
- operators can validate, invalidate, supersede, and promote memory through
  product-owned action boundaries
- workflow services can request durable memory through explicit retrieval
  policies instead of ambient graph access

That foundation is strong, but it is still concentrated in a narrow part of the
product:

- dashboard summaries do not yet expose repository memory freshness, memory
  action-needed state, or recent governed follow-up signals in a bounded,
  operator-first way
- work-item, evidence, and decision surfaces do not yet consistently host the
  same bounded memory context and operator actions that run detail now supports
- cross-graph navigation is strongest in a few surfaces, but not yet a uniform
  product contract across the remaining governed routes
- memory-aware workflow and governed follow-up still depend more on service
  callers than on consistent product-facing surface adoption

The next step is therefore not another graph primitive. The next step is
rolling the existing memory capability out across the remaining canonical
operator and governed surfaces.

## Decision

`Jido.Code` shall expand memory-graph product adoption into dashboard summaries
and the remaining canonical governed surfaces through product-owned services,
view models, and action boundaries.

The product-facing shape is:

- dashboard, work-item, evidence, and decision surfaces may host bounded
  memory and workflow-provenance context when that context helps explain
  governed state, freshness, or follow-up pressure
- operators may validate, invalidate, supersede, and promote memory from those
  canonical surfaces through the same product-owned action boundaries already
  used elsewhere, rather than through surface-local mutation paths
- memory and provenance navigation shall remain repository-scoped and product
  shaped across dashboard, managed-repository, run, work-item, evidence, and
  decision views
- workflow and governed follow-up surfaces may consume memory-aware summaries,
  suggestions, and retrieval results only through product-owned projections
  rather than raw graph responses
- all of those surfaces remain canonical product routes and governed views,
  not graph-browser shells or alternate semantic systems of record

## Consequences

- Memory graph adoption becomes broader and more uniform across operator and
  governance surfaces instead of feeling tied to only repository detail or run
  detail.
- Dashboard and governed summaries gain a clearer role as memory freshness and
  follow-up awareness surfaces without needing to become graph exploration
  tools.
- Operator memory actions stay consistent across surfaces because they continue
  to flow through the same product-owned mutation and capture-plane boundaries.
- Cross-graph navigation becomes a shared product concern rather than a
  surface-specific convenience.
- Governed records remain canonical because memory-backed insights and actions
  still matter to the factory only after they rejoin governed product state.
