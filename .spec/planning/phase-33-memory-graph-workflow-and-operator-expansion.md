# Phase 33 - Memory Graph Workflow And Operator Expansion

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/memory_graph/`
- `lib/jido_code/workbench/`
- `lib/jido_code/governance/`
- `lib/jido_code/orchestration/`
- `lib/jido_code_web/live/`
- `lib/jido_code_web/components/`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 28 through 32 established the memory-graph pod, capture plane, durable memory adoption, product-safe recovery, repository-detail memory inspection, and initial memory-aware workflow boundaries.
- The remaining work is to expand memory and provenance context into governed product surfaces, operator memory actions, and more explicit workflow retrieval behavior.
- Memory actions must continue to flow through product-owned boundaries and the canonical capture plane rather than introducing direct graph mutation or graph-local product truth.

[x] 33 Phase 33 - Memory Graph Workflow And Operator Expansion
  Expand bounded memory and workflow-provenance adoption into governed workflow surfaces, operator memory actions, and intent-specific workflow retrieval so memory becomes actionable across the canonical product.

  [x] 33.1 Section - Governed Surface Memory Context Expansion
    Extend bounded memory and provenance context from repository-detail surfaces into canonical governed run, work-item, evidence, and decision views.

    [x] 33.1.1 Task - Add product-owned memory context loaders for governed surfaces
      Establish the product-owned loading and view-model boundaries that let governed surfaces show memory and provenance context without becoming graph browsers.

      [x] 33.1.1.1 Subtask - Add governed run and work-item memory context loaders over the existing memory product service boundary.
      [x] 33.1.1.2 Subtask - Add bounded view-model shaping for evidence and decision history that highlights memory freshness, provenance, and related governed artifacts.
      [x] 33.1.1.3 Subtask - Keep governed surfaces canonical by presenting bounded memory context inside existing product routes instead of introducing graph-only route families.

    [x] 33.1.2 Task - Expand bounded cross-graph navigation across governed history
      Let operators move safely among code, memory, provenance, and governed records from any canonical surface that hosts memory context.

      [x] 33.1.2.1 Subtask - Add bounded navigation helpers from memory and provenance to governed runs, work items, evidence, and decisions.
      [x] 33.1.2.2 Subtask - Add bounded return navigation from governed records back to related code anchors and memory history.
      [x] 33.1.2.3 Subtask - Keep all navigation repository-scoped, freshness-aware, and explainable when dependencies are stale or recovering.

  [x] 33.2 Section - Operator Memory Actions And History Mutation
    Add product-owned operator actions for evolving memory over time while preserving the capture-plane and governed-record boundaries.

    [x] 33.2.1 Task - Add bounded operator memory mutation actions
      Give operators canonical product actions for validating, invalidating, superseding, and otherwise evolving durable memory state.

      [x] 33.2.1.1 Subtask - Add product-owned action helpers for validate and invalidate flows over durable-memory update envelopes.
      [x] 33.2.1.2 Subtask - Add product-owned supersession helpers that preserve links between superseded and successor memories.
      [x] 33.2.1.3 Subtask - Keep mutation flows product-safe by routing all writes through capture-plane update boundaries rather than direct graph writes.

    [x] 33.2.2 Task - Add operator-driven memory promotion and follow-up
      Let operators turn memory into explicit governed work or evidence without blurring the line between semantic support and product truth.

      [x] 33.2.2.1 Subtask - Add promotion helpers that turn a selected memory into governed follow-up inputs such as observation, assessment, work, evidence, or decision reconsideration.
      [x] 33.2.2.2 Subtask - Preserve freshness, supersession, revision, and provenance metadata when memory promotion re-enters the control plane.
      [x] 33.2.2.3 Subtask - Expose bounded operator affordances for these actions on the canonical product surfaces that already host the memory context.

  [x] 33.3 Section - Intent-Specific Memory Retrieval For Workflows
    Deepen workflow use of durable memory by making retrieval explicit, freshness-aware, and tied to workflow intent rather than broad generic recall.

    [x] 33.3.1 Task - Add intent-specific workflow retrieval policies
      Extend planner, reviewer, explainer, and governed follow-up boundaries so they can request the right memory for the current task.

      [x] 33.3.1.1 Subtask - Add retrieval policy options that name memory classes, freshness expectations, provenance scope, and bounded follow-up intent.
      [x] 33.3.1.2 Subtask - Ensure workflow callers receive bounded, product-shaped memory context instead of raw graph output.
      [x] 33.3.1.3 Subtask - Keep workflow behavior safe when memory is stale, invalidated, superseded, unavailable, or recovering.

    [x] 33.3.2 Task - Align governed workflow follow-up with durable memory state
      Make governed follow-up and later review explainable by preserving how memory participated in the workflow.

      [x] 33.3.2.1 Subtask - Add workflow provenance links that explain which durable memory informed a plan, review, explanation, or follow-up decision.
      [x] 33.3.2.2 Subtask - Preserve memory freshness, supersession, and evidence metadata when workflows emit governed follow-up.
      [x] 33.3.2.3 Subtask - Keep graph-backed workflow support bounded so governed records remain the canonical product truth.

  [x] 33.4 Section - Phase 33 Integration Tests
    Verify memory context, operator actions, and workflow retrieval stay bounded, explainable, and canonical across governed surfaces and follow-up flows.

    [x] 33.4.1 Task - Governed surface and operator-action scenarios
      Prove canonical governed surfaces can host memory context and product-owned memory actions without becoming graph browsers.

      [x] 33.4.1.1 Subtask - Add coverage proving run, work-item, evidence, or decision surfaces show bounded memory and provenance context through product-owned loaders.
      [x] 33.4.1.2 Subtask - Add coverage proving validate, invalidate, supersede, and promote actions route through bounded product and capture-plane boundaries.
      [x] 33.4.1.3 Subtask - Add coverage proving cross-graph navigation among memory, source code, and governed history remains repository-scoped and explainable.

    [x] 33.4.2 Task - Workflow retrieval and governed follow-up scenarios
      Prove workflow retrieval stays explicit and that memory-informed follow-up preserves the metadata needed for later reasoning.

      [x] 33.4.2.1 Subtask - Add coverage proving planner, reviewer, and explainer retrieval uses explicit memory policies instead of ambient recall.
      [x] 33.4.2.2 Subtask - Add coverage proving memory-informed follow-up preserves freshness, supersession, revision, and provenance metadata.
      [x] 33.4.2.3 Subtask - Verify the spec workspace remains coherent after Phase 33 expands memory workflow and operator adoption.
