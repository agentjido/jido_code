# Memory Graph Product Adoption

This subject defines how the repository-scoped memory graph becomes a
product-facing capability in canonical managed-repository surfaces and governed
workflow entrypoints.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.memory_graph_product_adoption
kind: feature
status: proposed
summary: Jido.Code adopts the repository-scoped memory and workflow-provenance graphs as bounded product capabilities by adding product-owned memory service, view-model, and cross-graph navigation boundaries over AgentWorkspace, hosting memory and provenance inspection inside canonical managed-repository routes, exposing freshness, validation, invalidation, stale, and recovery state in operator surfaces, allowing planning, review, and explanation workflows to request memory context explicitly through product-owned options instead of ambient graph assumptions, preserving repository-scoped recovery and bounded memory-capture rules when operator or governed paths record or evolve durable memories, and requiring memory findings to rejoin governed product records instead of exposing raw SPARQL, pod topology, or TripleStore internals to product callers.
decisions:
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.memory_graph_product_adoption
  - jido_code.memory_graph_workflow_and_operator_expansion
  - jido_code.source_code_graph_product_adoption
surface:
  - .spec/decisions/jido_code.memory_graph_product_adoption.md
  - .spec/decisions/jido_code.memory_capture_plane_and_insertion_seams.md
  - .spec/specs/memory_graph.spec.md
  - .spec/specs/memory_capture_plane.spec.md
  - .spec/specs/source_code_graph_product_adoption.spec.md
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/memory_graph/
  - lib/jido_code/memory_graph/product_service.ex
  - lib/jido_code/memory_graph/product_feedback.ex
  - lib/jido_code/memory_graph/finding.ex
  - lib/jido_code/memory_graph/materialization.ex
  - lib/jido_code/memory_graph/workflow_service.ex
  - lib/jido_code/memory_graph/governed_adoption.ex
  - lib/jido_code/workbench/
  - lib/jido_code/workbench/project_memory_inspection.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/workbench_live.ex
  - lib/jido_code_web/live/
  - lib/jido_code_web/components/
  - test/jido_code/memory_graph_product_service_test.exs
  - test/jido_code/memory_graph_workflow_service_test.exs
  - test/jido_code/memory_graph_governed_adoption_test.exs
  - test/jido_code/phase_thirty_two_integration_test.exs
  - test/jido_code_web/live/phase_thirty_two_integration_test.exs
  - test/jido_code/
  - test/jido_code_web/live/
```

## Requirements

```spec-requirements
- id: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  statement: Product code shall consume memory-graph capability through bounded product-owned service, feedback, and view-model boundaries over AgentWorkspace rather than by issuing raw SPARQL, reading pod internals, or opening TripleStore directly from UI-owned code.
  priority: must
  stability: proposed

- id: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  statement: Managed-repository operator routes shall be the canonical host surfaces for repository memory and workflow-provenance inspection instead of introducing a separate graph-only memory browser route family.
  priority: must
  stability: proposed

- id: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  statement: Operator-facing memory surfaces shall expose freshness, validation, invalidation, stale state, latest failure, and explicit recovery affordances so repository memory remains explainable and safe.
  priority: must
  stability: proposed

- id: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  statement: Planning, review, and explanation workflows shall request memory context explicitly through product-owned options or service calls rather than assuming ambient memory-graph availability.
  priority: should
  stability: proposed

- id: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
  statement: When durable memory or workflow-provenance findings influence factory behavior, those findings shall be materialized back into governed product records such as Observation, Assessment, WorkItem, Evidence, or Decision instead of remaining graph-local product truth.
  priority: must
  stability: proposed

- id: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  statement: Product operator surfaces shall present bounded memory and provenance projections, cross-links, and recovery affordances rather than raw SPARQL text, pod topology, graph-store handles, or low-level RDF details.
  priority: must
  stability: proposed

- id: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  statement: Product-facing memory and provenance views may navigate to stable repository-scoped code entities and related source-code graph projections through bounded cross-graph links, but those links shall remain product-owned projections rather than raw graph joins exposed directly to UI code.
  priority: should
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.memory_graph_product_adoption.scenario_repo_detail_hosts_memory_and_provenance_inspection
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  given:
    - A managed repository has memory-graph capability enabled.
  when:
    - An operator opens the repository detail surface to inspect durable memory or workflow provenance.
  then:
    - The route remains a canonical managed-repository product surface.
    - The page consumes memory and provenance through a product-owned boundary over AgentWorkspace.
    - The operator sees bounded memory and provenance projections without raw graph-engine internals.

- id: architecture.memory_graph_product_adoption.scenario_memory_surface_shows_stale_validation_and_recovery
  covers:
    - architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  given:
    - A repository has stale, invalidated, degraded, or failed memory-graph state.
  when:
    - An operator opens a memory or provenance surface or requests a memory-backed insight.
  then:
    - The product surface shows explicit freshness, validation, invalidation, and failure state.
    - The operator can trigger bounded recovery behavior through product-owned actions.
    - The product does not pretend the memory is current or hide the state behind raw runtime errors.

- id: architecture.memory_graph_product_adoption.scenario_workflow_requests_memory_context_explicitly
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  given:
    - A planning, review, or explanation workflow may benefit from repository memory and provenance.
  when:
    - The workflow opts into memory context.
  then:
    - The product-owned workflow boundary explicitly requests memory preparation and bounded memory projections.
    - Memory context is absent when the workflow does not request it.
    - Workflow logic remains independent of direct pod topology or raw SPARQL calls.

- id: architecture.memory_graph_product_adoption.scenario_memory_findings_become_governed_follow_up
  covers:
    - architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
  given:
    - Durable repository memory or workflow provenance suggests follow-up work, review evidence, or decision reconsideration.
  when:
    - The factory or an operator turns that finding into action.
  then:
    - The outcome is recorded through governed product records such as Observation, Assessment, WorkItem, Evidence, or Decision.
    - The memory graph remains a supporting semantic layer rather than the durable product system of record.

- id: architecture.memory_graph_product_adoption.scenario_memory_views_cross_link_to_source_code_safely
  covers:
    - architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  given:
    - A durable memory refers to one or more repository files, modules, functions, tests, or symbols.
  when:
    - An operator follows that relationship from a memory or provenance surface.
  then:
    - The product navigates through bounded cross-graph projections and stable repository-scoped identifiers.
    - UI-owned code does not construct raw graph joins or direct store queries itself.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_product_adoption.md
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
    - architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
    - architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
    - architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
    - architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code

- kind: source_file
  target: .spec/specs/memory_graph_product_adoption.spec.md
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
    - architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
    - architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
    - architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
    - architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code

- kind: source_file
  target: lib/jido_code/memory_graph/product_service.ex
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
    - architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code

- kind: source_file
  target: lib/jido_code/workbench/project_memory_inspection.ex
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
    - architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals

- kind: source_file
  target: lib/jido_code/memory_graph/workflow_service.ex
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals

- kind: source_file
  target: lib/jido_code/memory_graph/governed_adoption.ex
  covers:
    - architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code/memory_graph_workflow_service_test.exs
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context

- kind: source_file
  target: test/jido_code/memory_graph_governed_adoption_test.exs
  covers:
    - architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code/phase_thirty_two_integration_test.exs
  covers:
    - architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
    - architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
    - architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
    - architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code

- kind: source_file
  target: test/jido_code_web/live/phase_thirty_two_integration_test.exs
  covers:
    - architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
    - architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
    - architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
```
