# Source Code Graph Product Adoption

<!-- current_truth.reconciled_with_branch: source-code graph health, resource limits, product services, and bounded live surfaces remain under this subject. -->

This subject defines how the repository-scoped semantic source-code graph
becomes a product-facing capability in operator surfaces and governed workflow
entrypoints.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.source_code_graph_product_adoption
kind: feature
status: active
summary: Jido.Code adopts the repository-scoped source-code graph as a bounded product capability by adding product-owned semantic service, view-model, and semantic-finding materialization boundaries over AgentWorkspace, hosting semantic inspection inside canonical managed-repository routes, exposing freshness, stale, degraded, and recovery state in operator surfaces, enriching planning, review, and explanation flows only through explicit semantic requests, letting semantic workflow preparation and governed adoption extend the shared workflow-provenance capture plane through typed envelopes rather than raw triples, now emitting typed governed references from those capture requests instead of generic governed-context naming, using repository-scoped memory-graph recovery before bounded provenance or durable-memory capture proceeds, coexisting with bounded memory and provenance inspection in the same managed-repository and governed-run routes without leaking shared pod or store topology into product code, allowing those bounded workflow and adoption paths to emit typed memory-capture requests when durable lessons or decisions are intentionally classified, and requiring semantic findings to rejoin governed product records instead of exposing raw SPARQL, pod, or TripleStore internals while cross-graph links remain product-shaped on the cohosted surfaces.
decisions:
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
  - jido_code.live_vue_frontend_adoption
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
  - jido_code.source_code_graph_product_adoption
surface:
  - .spec/decisions/jido_code.source_code_graph_product_adoption.md
  - .spec/decisions/jido_code.memory_capture_plane_and_insertion_seams.md
  - .spec/specs/source_code_graph_pod.spec.md
  - .spec/specs/memory_capture_plane.spec.md
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/source_code_graph/
  - lib/jido_code/source_code_graph/product_service.ex
  - lib/jido_code/source_code_graph/product_feedback.ex
  - lib/jido_code/source_code_graph/memory_capture.ex
  - lib/jido_code/source_code_graph/workflow_service.ex
  - lib/jido_code/source_code_graph/governed_adoption.ex
  - lib/jido_code/source_code_graph/view_model.ex
  - lib/jido_code/source_code_graph/finding.ex
  - lib/jido_code/source_code_graph/materialization.ex
  - lib/jido_code/workbench/
  - lib/jido_code/workbench/project_semantic_inspection.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/workbench_live.ex
  - lib/jido_code_web/live/ProjectDetailSemanticExplorerWidget.vue
  - lib/jido_code_web/live/
  - lib/jido_code_web/components/
  - test/jido_code/source_code_graph_product_service_test.exs
  - test/jido_code/source_code_graph_workflow_service_test.exs
  - test/jido_code/source_code_graph_governed_adoption_test.exs
  - test/jido_code/source_code_graph_materialization_test.exs
  - test/jido_code/phase_twenty_four_integration_test.exs
  - test/jido_code/phase_twenty_six_integration_test.exs
  - test/jido_code/phase_twenty_seven_integration_test.exs
  - test/jido_code/source_code_graph_workspace_test.exs
  - test/jido_code_web/live/phase_twenty_five_integration_test.exs
  - test/jido_code_web/live/phase_twenty_seven_integration_test.exs
  - test/jido_code_web/live/
```

## Requirements

```spec-requirements
- id: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  statement: Product code shall consume source-code graph capability through bounded product-owned service or view-model boundaries over AgentWorkspace rather than by issuing raw SPARQL, calling pod internals, or opening TripleStore directly from UI-owned code.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  statement: Managed-repository operator routes shall be the canonical host surfaces for semantic repository inspection, including bounded module, function, runtime-pattern, and impact views, instead of introducing a separate graph-only browser route family.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  statement: Operator-facing semantic surfaces shall expose graph freshness, stale state, degraded-query state, latest failure, and explicit recovery actions so semantic inspection remains explainable and safe.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  statement: Planning, review, and explanation workflows shall request semantic graph context explicitly through product-owned workflow options or service calls rather than assuming ambient semantic availability.
  priority: should
  stability: proposed

- id: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  statement: When semantic findings influence factory behavior, those findings shall be materialized back into governed product records such as Observation, Assessment, WorkItem, Evidence, or Decision instead of remaining graph-local runtime facts.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  statement: Product operator surfaces shall present bounded semantic projections and recovery affordances rather than raw SPARQL text, pod topology, store handles, or graph-engine implementation details.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_product_adoption.governed_surfaces_may_cohost_semantic_cross_links
  statement: Governed run-detail or adjacent operator surfaces may host bounded source-code cross-links alongside memory and provenance context when those links are derived through product-owned semantic services, but the surfaces shall remain canonical governed routes rather than graph-browser shells.
  priority: should
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.source_code_graph_product_adoption.scenario_repo_detail_hosts_semantic_inspection
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  given:
    - A managed repository has source-code graph capability enabled.
  when:
    - An operator opens the repository detail surface to inspect semantic repository structure.
  then:
    - The route remains a canonical managed-repository product surface.
    - The page consumes semantic projections through a product-owned boundary over AgentWorkspace.
    - The operator sees bounded semantic views such as modules, functions, runtime patterns, or impact traces without raw graph-engine internals.
    - Co-located memory and provenance regions may coexist in the same route as long as semantic inspection remains bounded and product-owned.

- id: architecture.source_code_graph_product_adoption.scenario_semantic_surface_shows_stale_state_and_recovery
  covers:
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  given:
    - A repository has a stale, degraded, or failed semantic graph state.
  when:
    - An operator opens a semantic inspection surface or asks for graph-backed insight.
  then:
    - The product surface shows explicit freshness and failure state.
    - The operator can trigger bounded recovery behavior through product-owned actions.
    - The surface does not pretend the graph is fresh or hide recovery behind raw runtime errors.

- id: architecture.source_code_graph_product_adoption.scenario_workflow_requests_graph_context_explicitly
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  given:
    - A planning, review, or explanation workflow may benefit from repository semantics.
  when:
    - The workflow opts into semantic context.
  then:
    - The product-owned workflow boundary explicitly requests graph preparation and semantic projections.
    - Semantic context is absent when the workflow does not request it.
    - Workflow logic remains independent of direct pod topology or raw SPARQL calls.

- id: architecture.source_code_graph_product_adoption.scenario_semantic_findings_become_governed_work
  covers:
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  given:
    - Semantic inspection identifies a runtime pattern, dependency relationship, or bounded impact finding that deserves action.
  when:
    - The factory or an operator turns that finding into follow-up work or review evidence.
  then:
    - The outcome is recorded through governed product records such as Observation, Assessment, WorkItem, Evidence, or Decision.
    - The semantic graph remains a supporting capability rather than the durable control-plane system of record.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.source_code_graph_product_adoption.md
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: lib/jido_code/source_code_graph/product_service.ex
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: lib/jido_code/agent_workspace.ex
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
    - architecture.source_code_graph_product_adoption.governed_surfaces_may_cohost_semantic_cross_links

- kind: source_file
  target: lib/jido_code/source_code_graph/product_feedback.ex
  covers:
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: lib/jido_code/workbench/project_semantic_inspection.ex
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: lib/jido_code/source_code_graph/materialization.ex
  covers:
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context

- kind: source_file
  target: lib/jido_code/source_code_graph/memory_capture.ex
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: lib/jido_code/source_code_graph/workflow_service.ex
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: lib/jido_code/source_code_graph/governed_adoption.ex
  covers:
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code/source_code_graph_workflow_service_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context

- kind: source_file
  target: test/jido_code/source_code_graph_governed_adoption_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_nine_integration_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code/phase_twenty_four_integration_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code/phase_twenty_six_integration_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_five_integration_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: test/jido_code/phase_twenty_seven_integration_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code/phase_thirty_integration_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_seven_integration_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: test/jido_code_web/live/project_detail_live_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery

- kind: source_file
  target: test/jido_code_web/live/workbench_live_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
    - architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.source_code_graph_product_adoption.governed_surfaces_may_cohost_semantic_cross_links
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.source_code_graph_product_adoption.governed_surfaces_may_cohost_semantic_cross_links
    - architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
```
