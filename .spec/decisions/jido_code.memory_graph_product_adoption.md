---
id: jido_code.memory_graph_product_adoption
status: accepted
date: 2026-04-10
affects:
  - architecture.factory_control_plane
  - architecture.frontend_stack
  - architecture.memory_graph
  - architecture.memory_capture_plane
  - architecture.memory_graph_product_adoption
  - package.jido_code
related:
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.source_code_graph_product_adoption
  - jido_code.live_vue_frontend_adoption
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane -->
<!-- covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions -->
<!-- covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints -->
<!-- covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit -->
<!-- covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary -->
<!-- covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption -->
<!-- covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples -->
<!-- covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary -->
<!-- covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection -->
<!-- covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery -->
<!-- covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context -->
<!-- covers: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records -->
<!-- covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals -->
<!-- covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code -->

# Memory Graph Product Adoption

## Context

Phases 28 through 31 established the repository-scoped MemoryGraphPod, the
enhanced coding-memory ontology, the workflow-provenance capture plane, durable
memory adoption and validation behavior, and the product hardening needed to
keep that semantic stack safe and recoverable.

That foundation is necessary, but it is not yet a full product outcome. The
memory graph currently exists mainly as a runtime and service capability. It can
record durable facts, decisions, conventions, lessons, validation state, and
workflow provenance, but operators still do not have a canonical product path
for browsing that memory over time, understanding why a memory is stale or
invalidated, or moving from repository semantics into repository memory and back
again through normal managed-repository surfaces.

The next step is therefore not additional graph storage or capture mechanics.
The next step is adopting the memory graph as a bounded product capability in
the same way the source-code graph became a product capability in Phases 24
through 27.

## Decision

`Jido.Code` shall adopt the repository-scoped memory graph as a bounded
product-facing capability over `AgentWorkspace`, not merely as a pod-local
semantic store.

The product-facing shape is:

- managed-repository routes remain the canonical host surfaces for inspecting
  repository memory and workflow provenance
- product code consumes memory and provenance through bounded product-owned
  services and view models over `AgentWorkspace`, not through direct pod,
  TripleStore, or SPARQL access from UI-owned code
- operators may inspect durable memories such as facts, decisions, conventions,
  invariants, known issues, open questions, patterns, and anti-patterns, along
  with their provenance, freshness, validation, and invalidation state
- memory and provenance views may cross-link to source-code entities and
  governed product records, but the UI still must not expose raw graph-engine
  internals or ad hoc query text as the product interface
- planning, review, explanation, and governed follow-up flows may explicitly
  request memory context, but ambient memory availability is not assumed
- memory findings that materially affect the factory must still rejoin governed
  product records such as `Observation`, `Assessment`, `WorkItem`, `Evidence`,
  or `Decision`

This means the memory graph becomes a repository-scoped semantic product
support capability:

- it helps operators understand why the factory believes certain repository
  facts, conventions, or known issues
- it makes decision history, lessons learned, and validation status explorable
  over time
- it lets the product move from source-code entities to memories and provenance
  through bounded cross-graph navigation
- it does not become an alternate control plane or a free-form note browser

## Consequences

- The memory graph now has a clear product destination instead of remaining only
  a runtime semantic layer.
- Managed-repository surfaces can present memory freshness, invalidation,
  recovery, provenance, and decision history through canonical product routes
  instead of bespoke runtime tools.
- Product behavior remains explainable because memory views can expose why a
  fact exists, what code it refers to, what revision it was observed in, what
  evidence validated it, and why it may now be stale or invalid.
- Cross-graph navigation becomes a first-class product concern: source-code
  graph inspection can lead to durable memories and workflow provenance, and
  memory/provenance inspection can lead back to affected symbols and governed
  product records.
- The control plane remains canonical because memory findings still matter to
  factory behavior only when bounded product or governed paths adopt them.
- The product must now own memory-specific service boundaries, view models,
  operator affordances, and recovery-safe UI states rather than leaving those
  concerns implicit in runtime helpers.
