---
id: jido_code.source_code_graph_product_adoption
status: accepted
date: 2026-04-09
affects:
  - architecture.factory_control_plane
  - architecture.frontend_stack
  - architecture.source_code_graph_pod
  - architecture.source_code_graph_product_adoption
  - package.jido_code
related:
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
  - jido_code.live_vue_frontend_adoption
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane -->
<!-- covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions -->
<!-- covers: architecture.source_code_graph_pod.product_surfaces_consume_workspace_bound_semantic_projections -->
<!-- covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary -->
<!-- covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection -->
<!-- covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery -->
<!-- covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context -->
<!-- covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records -->
<!-- covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals -->

# Source Code Graph Product Adoption

## Context

Phases 20 through 23 established the repository-scoped `SourceCodeGraphPod`,
full-mode `ElixirOntologies` analysis, named-graph loading into local
`TripleStore`, and bounded SPARQL-backed query entrypoints through
`AgentWorkspace`.

That runtime foundation is necessary, but it is not yet the full product
outcome. If the semantic graph remains only a pod-local specialist capability,
operators still cannot inspect semantic repository structure through the normal
managed-repository UI, and governed work creation still cannot explicitly reuse
semantic findings without each feature inventing its own private query path.

The next product step is therefore not "more graph runtime." It is to adopt the
existing graph capability into product-owned services, operator surfaces, and
governed workflow entrypoints while preserving the factory control-plane model.

## Decision

`Jido.Code` shall adopt the source-code graph as a bounded product capability,
not merely an AgentOS runtime detail.

The product-facing shape is:

- managed-repository routes remain the canonical host surfaces for semantic
  inspection and action
- product code consumes semantic information through bounded product-owned
  services that call `AgentWorkspace`, not through direct pod or store access
- semantic operator views may use LiveView-hosted `live_vue` regions where
  richer graph exploration is useful, but LiveView remains the routed shell and
  server-authored source of truth
- semantic findings that matter to the factory must rejoin governed product
  records such as `Observation`, `Assessment`, `WorkItem`, `Evidence`, or
  `Decision` instead of remaining ephemeral graph-only facts
- graph freshness, stale state, degraded query behavior, and recovery actions
  must remain visible at the product surface so operators do not mistake a
  stale semantic snapshot for current truth

The graph therefore becomes a repository-scoped semantic support capability for
the control plane:

- it informs operator understanding
- it can enrich planning, review, and explanation flows
- it can help operators decide what work to create
- it does not replace Ash-backed product truth or become an alternate durable
  business record system

## Consequences

- The semantic graph now has a clear product destination instead of remaining a
  runtime-only specialist feature.
- The product foundation for that destination now includes a bounded
  `SourceCodeGraph.ProductService`, repo-first semantic view models, and
  explicit semantic-finding materialization helpers that can create governed
  `Observation` and `Assessment` records or build work and evidence inputs
  without leaking SPARQL or pod metadata into product callers.
- Managed-repository UI and workflow entrypoints can expose semantic structure,
  runtime patterns, and bounded impact traces without leaking SPARQL, pod
  topology, or store handles.
- Canonical repo detail and workbench surfaces now reuse one product-owned
  semantic inspection boundary, making semantic freshness and recovery visible
  in normal managed-repository routes instead of a separate graph browser.
- Product behavior stays explainable because semantic freshness and recovery
  remain explicit in operator-visible state.
- The control plane remains canonical: semantic outputs matter only when they
  are materialized back into governed product records.
