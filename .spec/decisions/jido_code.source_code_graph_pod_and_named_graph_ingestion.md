---
id: jido_code.source_code_graph_pod_and_named_graph_ingestion
status: accepted
date: 2026-04-08
affects:
  - package.jido_code
  - architecture.agent_os_integration
  - architecture.source_code_graph_pod
  - docs.product_foundation
related:
  - jido_code.jido_agent_os_integration
  - jido_code.jido_os_deprecation
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled -->
<!-- covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod -->
<!-- covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required -->
<!-- covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store -->
<!-- covers: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target -->
<!-- covers: architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together -->
<!-- covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query -->
<!-- covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface -->
<!-- covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently -->

# Source Code Graph Pod And Named Graph Ingestion

## Context

`Jido.Code` no longer carries the earlier generic knowledge-graph subsystem.
At the same time, the current AgentOS direction gives us a better place to add
repository-scoped semantic analysis without reintroducing an ambient singleton
service.

Two external building blocks now make a more explicit design viable:

- `elixir-ontologies` can analyze an Elixir project into RDF with Elixir-aware
  ontology terms, OTP/runtime modeling, provenance, and optional full
  expression-level extraction.
- `triple_store` can persist RDF locally with named graphs and SPARQL-capable
  query/update semantics.

The desired product outcome is narrower than a general-purpose graph platform.
For each managed repository, we want a durable local source-code graph that:

- analyzes the repository in full Elixir ontology mode
- loads the ontology and extracted individuals into a canonical named graph
  called `source_code`
- remains queryable by pod-local agents afterward through explicit tools

This capability belongs naturally inside the repository-scoped AgentOS kernel
model rather than in top-level product controllers or in a resurrected
cross-repository KG service.

## Decision

`Jido.Code` shall add a repository-scoped `SourceCodeGraphPod` within the
ManagedRepo kernel model.

When enabled for a managed repository, that pod shall be the canonical
repository-local semantic analysis surface. It shall own:

- analysis of the repository with `elixir-ontologies`
- use of the full ontology extraction profile, including expression-level
  detail rather than the light structural profile
- loading of ontology schema terms and repository-derived individuals into a
  local `triple_store` database configured for named-graph storage
- use of the named graph `source_code` as the canonical target for that
  repository's source-code graph load
- explicit query actions that let pod agents ask SPARQL questions against the
  resulting graph through the `sparql` library

The pod shall be repository-scoped rather than work-item-scoped. It is not a
replacement for `RepoPod` or `CodingPod`; it is an additional specialist pod for
durable source analysis and semantic query within one managed repository's
kernel boundary.

The expected pod shape is:

- one eager context/state agent that knows workspace path, local graph-store
  path, graph name, ontology profile, latest imported revision, and import
  status
- lazy specialist agents for ontology analysis, graph loading/refresh, and
  graph query
- explicit `Jido.Action` tools for analyze, load, refresh, and query behavior

The canonical storage and query split shall be:

- `triple_store` owns persisted RDF storage and named-graph durability
- `elixir-ontologies` owns Elixir-aware ontology extraction
- `sparql` owns the pod-local agent query surface for authoring/parsing and
  executing the post-load query workflow

The canonical named graph for this capability shall be exactly `source_code`.

## Consequences

- `Jido.Code` will gain a repository-local semantic capability without
  reintroducing the removed generic KG subsystem.
- The source-code graph becomes a durable repository-scoped asset, not an ad hoc
  transient analysis result hidden inside one agent prompt.
- Full ontology mode increases detail and likely storage/runtime cost, so graph
  refresh should be explicit and coherent rather than ambient on every minor
  event.
- Named-graph replacement semantics need to avoid mixed revisions, since the
  same `source_code` graph will hold both ontology-backed schema and extracted
  project individuals for one repository snapshot.
- Future coding or review flows may consult this pod, but the semantic store
  remains a bounded specialist capability rather than the product's source of
  durable truth.

## Implementation Note

Phase 20 now establishes the product-owned foundation for this decision inside
`jido_code`:

- a repository-scoped `SourceCodeGraphPod` contract with one eager graph context
  agent and lazy specialist agents for analyze, load/refresh, and query work
- a product-owned `SourceCodeGraph` boundary that fixes the canonical graph name
  to `source_code`, the ontology profile to `full`, and the repository-local
  TripleStore path shape
- explicit Jido actions for analyze, load, refresh, status, query, and bounded
  dataset inspection behavior
- `AgentWorkspace` entrypoints that ensure the capability, hide pod topology,
  preserve repository-scoped readiness, and fail closed on disabled or not-ready
  graph states

Phase 21 extends that foundation with the first real semantic ingestion path:

- `ElixirOntologies.analyze_project/2` now runs in explicit full mode with
  expression-level extraction enabled and repository revision metadata preserved
  in the staged analysis result
- ontology schema artifacts and repository-derived individuals are normalized
  into one coherent intermediate snapshot before import
- a repository-local `TripleStore` quad store is opened through a staged-store
  swap strategy that loads ontology schema and project individuals into the
  canonical named graph IRI for `source_code`
- refresh replaces the canonical store coherently rather than mutating a live
  mixed snapshot in place
- `AgentWorkspace` now preserves repository-scoped analysis/import status,
  imported revision, and typed stale-revision outcomes through the pod metadata
  boundary

Phase 22 begins the semantic query surface on top of that stored graph:

- `QuerySourceCodeGraph` now validates and executes SPARQL through the `sparql`
  library while targeting the repository-local `source_code` named graph from
  `TripleStore`
- query results are returned as bounded product-shaped rows and metadata rather
  than raw store handles or internal result structs
- helper actions now compile common module, function, runtime-pattern, and
  bounded impact lookups down to explicit SPARQL queries instead of introducing
  an ambient hidden semantic side channel

Phase 22.2 extends that query surface into the pod and selected coding
specialists:

- the SourceCodeGraph analyzer, loader, and querier agents now expose explicit
  bounded signal routes and state shapes for analysis, refresh, query, and
  helper-query activity
- the querier specialist now owns explicit helper routes for module, function,
  runtime-pattern, and bounded impact lookups instead of generic hidden graph
  inspection
- selected coding specialists (planner, reviewer, explainer) now receive
  semantic graph tools through explicit composition, while coder and refactorer
  remain free of semantic graph tooling by default
- prompts now state that semantic lookup is an explicit tool call gated by
  repository readiness rather than an ambient assumption

Phase 22.3 brings the semantic graph into product-owned workflow boundaries:

- `AgentWorkspace` now exposes repository-scoped helper entrypoints for module,
  function, runtime-pattern, impact, and direct SPARQL lookup without exposing
  pod topology
- planning, review, and explanation flows can now request explicit semantic
  inputs through bounded `source_code_graph` workflow options instead of
  assuming the graph exists ambiently
- workflow semantic preparation explicitly chooses whether to check status,
  load-if-missing, or refresh before query, keeping graph refresh decisions
  product-owned and visible
- workflow consumers receive bounded semantic context maps, while durable
  product truth remains outside the semantic graph itself

Phase 22.4 closes the phase with end-to-end repository coverage:

- integration tests now prove repository-local load, query, and refresh all
  operate through the canonical `sparql` and `source_code` graph boundaries
- workspace helper entrypoints now show bounded module, function,
  runtime-pattern, and impact lookups without leaking pod or store topology
- higher-level plan and explanation flows now demonstrate that semantic graph
  inputs only appear when explicitly requested through workspace options, not as
  an ambient dependency
