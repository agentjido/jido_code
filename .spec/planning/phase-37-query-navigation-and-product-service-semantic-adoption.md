# Phase 37 - Query, Navigation, And Product Service Semantic Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints -->
<!-- covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance -->
<!-- covers: architecture.run_governance.run_detail_can_host_bounded_memory_context -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `lib/jido_code/memory_graph/helper_queries.ex`
- `lib/jido_code/memory_graph/cross_graph_navigation.ex`
- `lib/jido_code/memory_graph/product_service.ex`
- `lib/jido_code/memory_graph/operator_service.ex`
- `lib/jido_code/memory_graph/workflow_service.ex`
- `lib/jido_code/memory_graph/materialization.ex`
- `lib/jido_code/source_code_graph/materialization.ex`
- `lib/jido_code/source_code_graph/governed_adoption.ex`
- `lib/jido_code/agent_workspace.ex`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 35 and 36 established typed governed ontologies, IRIs, capture contracts, and writer semantics.
- The current query and navigation layer still relies on generic `artifact` vocabulary and only has one canonical typed route today.
- Product, operator, and workflow services must continue to expose bounded projections instead of raw SPARQL or pod/store internals.
- Where a governed record has no canonical route yet, the stronger semantic model should still return a typed label and id rather than a broken route.

[x] 37 Phase 37 - Query, Navigation, And Product Service Semantic Adoption
  Cut product-facing query, navigation, and service boundaries over to the stronger governed semantic model so bounded memory and provenance surfaces stop speaking in generic artifact terms.

  [x] 37.1 Section - Query And Cross-Graph Navigation Semantic Cutover
    Update memory/provenance queries and navigation shaping so typed governed records become first-class results and links.

    [x] 37.1.1 Task - Replace generic artifact filters and projections in helper queries
      Make typed governed references queryable and explainable from bounded product projections rather than relying on generic `supportedBy ?artifact` patterns.

      [x] 37.1.1.1 Subtask - Update helper queries to filter and project typed governed record kinds, ids, labels, and links for memory and provenance lookups.
      [x] 37.1.1.2 Subtask - Replace generic artifact terminology in result shaping with governed-record terminology that matches the product domain.
      [x] 37.1.1.3 Subtask - Preserve bounded source-code anchors, freshness metadata, and evidence links alongside the stronger governed semantics.

    [x] 37.1.2 Task - Upgrade cross-graph navigation to typed governed links
      Turn cross-graph navigation into a semantically strong projection over code, memory, provenance, and governed product history.

      [x] 37.1.2.1 Subtask - Update navigation shaping to resolve typed `run`, `work_item`, `evidence`, `decision`, `observation`, `assessment`, and `change_request` references.
      [x] 37.1.2.2 Subtask - Add canonical routes where they exist and typed labels where no route is yet available, without falling back to broken generic links.
      [x] 37.1.2.3 Subtask - Keep navigation repository-scoped, freshness-aware, and explicit about stale or recovering dependencies.

  [x] 37.2 Section - Product, Operator, And Workflow Service Adoption
    Align the higher-level memory services with typed governed references so product behavior, operator actions, and workflow retrieval all use the stronger semantic model consistently.

    [x] 37.2.1 Task - Cut product and operator services over to typed governed references
      Replace mixed id-map and generic artifact assumptions in the product-facing boundaries with typed governed-context behavior.

      [x] 37.2.1.1 Subtask - Update `ProductService`, `OperatorService`, and related view-model shaping to consume typed governed references rather than generic artifact paths.
      [x] 37.2.1.2 Subtask - Preserve validate, invalidate, supersede, and promote flows while shaping their feedback around typed governed records and provenance.
      [x] 37.2.1.3 Subtask - Keep operator and product callers insulated from raw ontology details even though the stored semantics become stronger.

    [x] 37.2.2 Task - Improve workflow and materialization seams with stronger semantics
      Ensure memory-aware workflows and governed adoption preserve typed links when they turn semantic support into product follow-up.

      [x] 37.2.2.1 Subtask - Update workflow retrieval and follow-up helpers so typed governed references survive planner, reviewer, explainer, and adoption flows.
      [x] 37.2.2.2 Subtask - Update memory and source-code materialization seams so created observations, assessments, work items, evidence, and decisions emit typed semantic references immediately.
      [x] 37.2.2.3 Subtask - Keep governed records the canonical truth while making the semantic links around them much stronger and more queryable.

  [x] 37.3 Section - Phase 37 Integration Tests
    Verify queries, navigation, and bounded services all reflect the stronger semantic model before surface rollout and rebuild hardening continue.

    [x] 37.3.1 Task - Query and navigation scenarios
      Prove memory and provenance results now return typed governed semantics end to end.

      [x] 37.3.1.1 Subtask - Add coverage proving helper queries filter and project typed governed references instead of generic artifacts.
      [x] 37.3.1.2 Subtask - Add coverage proving cross-graph navigation returns correct typed labels, ids, and routes for governed records.
      [x] 37.3.1.3 Subtask - Add coverage proving stale or recovering graph state still produces bounded, explainable navigation behavior.

    [x] 37.3.2 Task - Product and workflow service scenarios
      Prove product, operator, and workflow boundaries now consume and emit typed governed semantics consistently.

      [x] 37.3.2.1 Subtask - Add coverage proving product and operator services no longer depend on generic artifact terminology or path shapes.
      [x] 37.3.2.2 Subtask - Add coverage proving workflow retrieval and governed follow-up preserve typed governed references through memory-aware flows.
      [x] 37.3.2.3 Subtask - Verify the spec workspace remains coherent after Phase 37 cuts product services and navigation over to the stronger semantic model.
