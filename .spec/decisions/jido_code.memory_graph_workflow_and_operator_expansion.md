---
id: jido_code.memory_graph_workflow_and_operator_expansion
status: accepted
date: 2026-04-10
affects:
  - architecture.factory_control_plane
  - architecture.frontend_stack
  - architecture.memory_graph
  - architecture.memory_capture_plane
  - architecture.memory_graph_product_adoption
  - architecture.memory_graph_workflow_and_operator_expansion
  - package.jido_code
related:
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.memory_graph_product_adoption
  - jido_code.source_code_graph_product_adoption
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane -->
<!-- covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions -->
<!-- covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints -->
<!-- covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary -->
<!-- covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence -->
<!-- covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples -->
<!-- covers: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up -->

# Memory Graph Workflow And Operator Expansion

## Context

Phases 28 through 32 established the repository-scoped MemoryGraphPod, the
capture plane, durable memory adoption and validation, and the initial
product-facing memory inspection model inside canonical managed-repository
surfaces.

That foundation is now strong enough that the remaining gap is no longer basic
memory visibility. The remaining gap is operational and workflow depth:

- governed run, work, evidence, and decision surfaces still need a canonical
  way to show the memories and workflow provenance that informed them
- operators still need bounded product actions for validating, invalidating,
  superseding, and promoting memory instead of relying on runtime-only helpers
- planner, reviewer, and explainer flows need durable memory retrieval rules
  that are explicit, freshness-aware, and intent-specific instead of treating
  memory as a generic optional blob
- cross-graph navigation now needs to move safely among memory, provenance,
  source code, and governed history instead of stopping at repository detail

The next step is therefore not a new graph store or a new ontology. The next
step is expanding the memory graph from repository-detail adoption into
governed workflow and operator action surfaces.

## Decision

`Jido.Code` shall expand bounded memory-graph product adoption into canonical
governed workflow and operator surfaces through product-owned service and action
boundaries.

The product-facing shape is:

- managed-repository routes remain the semantic home for repository context, but
  governed run, work-item, evidence, and decision surfaces may now host bounded
  memory and provenance context when those governed records were informed by
  durable memory
- operators may validate, invalidate, supersede, and promote memory only
  through product-owned actions that emit canonical capture-plane update
  requests instead of mutating the graph directly
- cross-graph navigation may move among memories, workflow provenance,
  source-code entities, runs, work items, evidence, and decisions through
  product-owned projections rather than raw SPARQL or direct RDF exposure
- planner, reviewer, and explainer workflows may request durable memory through
  explicit retrieval policies that name freshness expectations, memory classes,
  provenance needs, and bounded follow-up intent
- memory promotions that matter to the factory still re-enter governed product
  records rather than establishing graph-local truth as the system of record

This means the memory graph becomes a deeper workflow and operator support
plane:

- governed history can explain which memory or provenance influenced a run,
  review, evidence item, or later decision
- operators can evolve memory safely over time through explicit product actions
  instead of hidden runtime repair paths
- workflow services can retrieve the right memory for the current intent rather
  than treating all memory as undifferentiated context

## Consequences

- Run detail, work-item, evidence, and decision surfaces now have a clear
  architectural path for memory and provenance context without becoming graph
  browsers.
- The capture plane becomes more important because operator memory actions must
  use the same bounded insertion and update seam as runtime and workflow
  capture.
- Memory freshness, validation, invalidation, supersession, and provenance
  remain explicit even as memory becomes more actionable.
- Cross-graph navigation grows into a first-class product concern that spans
  repository context, source code, memory, workflow provenance, and governed
  history.
- Workflow services must now define retrieval intent clearly so durable memory
  is used deliberately and explainably.
- The control plane remains canonical because memory actions and promotions only
  matter to the factory after they rejoin governed product records.
