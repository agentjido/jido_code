# Memory Graph Workflow And Operator Expansion

<!-- current_truth.reconciled_with_branch: governed-route memory actions, cross-graph navigation, and follow-up provenance continue to live under this subject. -->

This subject defines how the repository-scoped memory graph expands from
repository-detail adoption into governed workflow surfaces, operator memory
actions, and intent-specific memory retrieval.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.memory_graph_workflow_and_operator_expansion
kind: feature
status: active
summary: Jido.Code now hosts bounded repository memory and workflow-provenance context across canonical governed run, work-item, evidence, and decision surfaces, routes validate, invalidate, supersede, and promote follow-up actions through product-owned memory boundaries over the capture plane rather than raw graph mutation, standardizes bounded cross-graph navigation among memory, workflow provenance, source-code entities, and governed records through the companion control-plane ontology plus typed governed references, lets planner, coder, reviewer, and explainer flows request durable memory through explicit retrieval policies keyed to freshness, memory class, provenance scope, and follow-up intent, and keeps memory-derived behavior explainable by preserving freshness, supersession, provenance, governed follow-up previews, recovery affordances, and governed adoption metadata whenever operators or workflows act on durable memory.
decisions:
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.memory_graph_product_adoption
  - jido_code.memory_graph_workflow_and_operator_expansion
surface:
  - .spec/decisions/jido_code.memory_graph_product_adoption.md
  - .spec/decisions/jido_code.memory_graph_workflow_and_operator_expansion.md
  - .spec/specs/memory_graph.spec.md
  - .spec/specs/memory_capture_plane.spec.md
  - .spec/specs/memory_graph_product_adoption.spec.md
  - .spec/planning/phase-33-memory-graph-workflow-and-operator-expansion.md
  - .spec/planning/phase-45-memory-aware-execute-workflow-adoption.md
  - .spec/planning/phase-55-memory-rollout-and-governed-surfaces.md
  - lib/jido_code/memory_graph/
  - lib/jido_code_web/governed_memory_helpers.ex
  - lib/jido_code/workbench/
  - lib/jido_code_web/live/
  - test/jido_code/
  - test/jido_code_web/live/
```

## Requirements

```spec-requirements
- id: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  statement: Canonical governed run, work-item, evidence, and decision surfaces may host bounded memory and workflow-provenance context when those records were informed by repository memory, but they shall remain governed product surfaces rather than graph-only views and shall keep typed governed links plus recovery affordances inside those same product routes.
  priority: must
  stability: proposed

- id: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
  statement: Operator-facing memory actions such as validate, invalidate, supersede, or promote follow-up shall route through product-owned action boundaries over AgentWorkspace and governed services rather than raw graph mutation or direct pod calls from UI-owned code.
  priority: must
  stability: proposed

- id: architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
  statement: Product-owned memory mutations shall emit canonical durable-memory update or capture requests through the memory capture plane instead of writing raw RDF updates directly.
  priority: must
  stability: proposed

- id: architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
  statement: Planner, coder, reviewer, explainer, and governed follow-up flows shall request durable memory through explicit retrieval policies that name freshness expectations, memory classes, provenance needs, and bounded follow-up intent rather than relying on ambient recall or broad raw queries.
  priority: must
  stability: proposed

- id: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  statement: Product-facing memory navigation shall support bounded links among memories, workflow provenance, source-code entities, runs, work items, evidence, and decisions through stable repository-scoped projections rather than exposing ad hoc graph joins or raw RDF identifiers as the UI contract.
  priority: should
  stability: proposed

- id: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  statement: Validation, invalidation, supersession, and promotion behavior shall preserve explicit freshness, revision, supersession, provenance, and evidence metadata so later operators can understand why a memory changed state.
  priority: must
  stability: proposed

- id: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  statement: When an operator or workflow promotes a memory into action, the resulting follow-up shall re-enter governed product records such as Observation, Assessment, WorkItem, Evidence, or Decision instead of remaining only a graph-local state change.
  priority: must
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.memory_graph_workflow_and_operator_expansion.scenario_run_and_governance_surfaces_show_memory_context
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  given:
    - A governed run, evidence item, or later decision was informed by repository memory or workflow provenance.
  when:
    - An operator opens the canonical governed surface for that record.
  then:
    - The surface may show bounded memory and provenance context.
    - The operator can navigate to related code and governed history without leaving the canonical product route family.
    - Typed governed links remain visible even when a governed record resolves to an anchored route on the current run surface or only to a typed label.

- id: architecture.memory_graph_workflow_and_operator_expansion.scenario_operator_validates_invalidates_or_supersedes_memory
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  given:
    - An operator determines that a durable memory should be validated, invalidated, or superseded.
  when:
    - The operator performs that action through the product.
  then:
    - The product issues a bounded memory action through product-owned services.
    - The resulting state change flows through canonical capture-plane update semantics.
    - Later readers can see freshness, supersession, provenance, and evidence context for the change.

- id: architecture.memory_graph_workflow_and_operator_expansion.scenario_workflow_requests_memory_by_intent
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  given:
    - A planner, coder, reviewer, or explainer workflow may benefit from durable memory.
  when:
    - The workflow opts into memory retrieval.
  then:
    - The workflow names bounded retrieval intent such as freshness expectations, relevant memory classes, and provenance scope.
    - Implementation workflows can ask for coding constraints, known issues, patterns, and recent plan or review history without receiving raw graph output.
    - The workflow receives product-shaped memory input instead of raw graph output.

- id: architecture.memory_graph_workflow_and_operator_expansion.scenario_memory_promotion_creates_governed_follow_up
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  given:
    - A durable memory reveals new work, review evidence, or a decision reconsideration need.
  when:
    - The operator or workflow promotes that memory into follow-up.
  then:
    - The promotion creates or enriches governed product records.
    - The memory graph remains a semantic support layer rather than the product system of record.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_workflow_and_operator_expansion.md
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
    - architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: .spec/specs/memory_graph_workflow_and_operator_expansion.spec.md
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
    - architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: .spec/planning/phase-33-memory-graph-workflow-and-operator-expansion.md
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
    - architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: .spec/planning/phase-45-memory-aware-execute-workflow-adoption.md
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance

- kind: source_file
  target: .spec/planning/phase-55-memory-rollout-and-governed-surfaces.md
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: lib/jido_code/memory_graph/surface_feedback.ex
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance

- kind: source_file
  target: lib/jido_code/memory_graph/governed_surface_context.ex
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history

- kind: source_file
  target: lib/jido_code/memory_graph/operator_service.ex
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: lib/jido_code_web/components/memory_surface_components.ex
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history

- kind: source_file
  target: lib/jido_code_web/live/work_item_detail_live.ex
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: lib/jido_code_web/live/evidence_detail_live.ex
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: lib/jido_code_web/live/decision_detail_live.ex
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance

- kind: source_file
  target: test/jido_code/phase_thirty_seven_integration_test.exs
  covers:
    - architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
    - architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
    - architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies
    - architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
    - architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
```
