# Phase 45 - Memory-Aware Execute Workflow Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary -->
<!-- covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_workflows_use_explicit_retrieval_policies -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `lib/jido_code/memory_graph/workflow_service.ex`
- `lib/jido_code/memory_graph/retrieval_policy.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agents/coder.ex`
- `test/jido_code/memory_graph_workflow_service_test.exs`
- `test/jido_code/agent_workspace_test.exs`

## Relevant Assumptions / Defaults
- Phase 33 introduced intent-specific memory retrieval for planner, reviewer, explainer, and governed follow-up paths, but the canonical execute or coder workflow still lacks a matching product-owned memory boundary.
- `AgentWorkspace.execute_work/4` can already carry bounded `:memory_graph` context, so the remaining work is to add the product-owned retrieval and shaping layer rather than a new raw graph access path.
- Coding workflows should receive bounded, freshness-aware, implementation-focused memory and provenance context instead of raw SPARQL, pod topology, or unbounded semantic recall.

[x] 45 Phase 45 - Memory-Aware Execute Workflow Adoption
  Add a product-owned memory-aware execute workflow so coder paths can request bounded durable memory and provenance context through the canonical workspace boundary.

  [x] 45.1 Section - Product-Owned Execute Memory Boundary
    Extend the bounded memory workflow service so execution and coding flows can request the same kind of explicit, freshness-aware memory context already available to other workflows.

    [x] 45.1.1 Task - Add execute workflow retrieval and policy defaults
      Introduce the product-owned execute memory entrypoint and retrieval defaults that turn coder memory use into a first-class, explainable workflow option.

      [x] 45.1.1.1 Subtask - Add `MemoryGraph.WorkflowService.execute/4` and the workflow-kind routing needed to prepare bounded memory context for `AgentWorkspace.execute_work/4`.
      [x] 45.1.1.2 Subtask - Add implementation-focused retrieval-policy defaults that emphasize decisions, invariants, conventions, known issues, patterns, and bounded plan, review, or patch provenance.
      [x] 45.1.1.3 Subtask - Keep execute memory requests product-owned and explicit by continuing to reject raw SPARQL or direct pod access from callers.

    [x] 45.1.2 Task - Shape bounded execute memory input and follow-up context
      Make the execute workflow payload coder-safe and product-readable while preserving the provenance needed for later governed follow-up.

      [x] 45.1.2.1 Subtask - Pass bounded graph, freshness, policy, and selection state into `AgentWorkspace.execute_work/4` through the existing `:memory_graph` payload.
      [x] 45.1.2.2 Subtask - Preserve selected durable-memory items, bounded provenance items, governed references, and related resources in the execute workflow context instead of raw graph query output.
      [x] 45.1.2.3 Subtask - Add execute follow-up shaping that records which durable memory informed the coding workflow and preserves that context for later governed actions.

  [x] 45.2 Section - Coding Workflow Runtime Adoption
    Route the new execute memory context through the canonical workspace and coder-specialist flow without leaking graph internals or weakening degraded-path behavior.

    [x] 45.2.1 Task - Route execute memory through AgentWorkspace and the coder specialist
      Ensure the coding runtime receives the right bounded context at the right scope while keeping callers insulated from pod and graph topology.

      [x] 45.2.1.1 Subtask - Invoke the memory-aware execute workflow through `AgentWorkspace.execute_work/4` rather than introducing a coder-only graph shortcut.
      [x] 45.2.1.2 Subtask - Ensure prompt and tool-context injection give the coder workflow, freshness, policy, and selected memory context at the same managed-repository and work-item scope.
      [x] 45.2.1.3 Subtask - Keep execute memory support optional so coding flows remain legible when memory is absent, stale, invalidated, disabled, or recovering.

    [x] 45.2.2 Task - Keep coder memory bounded, fresh, and implementation-focused
      Make sure the new execute workflow uses durable memory as a constraint and history aid rather than as an unbounded second source of truth.

      [x] 45.2.2.1 Subtask - Filter invalidated or stale durable memory by default unless the retrieval policy explicitly allows degraded use.
      [x] 45.2.2.2 Subtask - Prefer implementation-relevant memory and provenance such as decisions, invariants, conventions, known issues, patterns, plans, reviews, and patches.
      [x] 45.2.2.3 Subtask - Keep the coder payload product-readable by avoiding raw SPARQL text, graph-store handles, or unbounded semantic recall.

  [x] 45.3 Section - Phase 45 Integration Tests And Spec Convergence
    Verify the new execute memory path stays bounded, explainable, and coherent with the current-truth memory workflow specs.

    [x] 45.3.1 Task - Execute workflow memory retrieval scenarios
      Prove the new execute path behaves like the other memory-aware workflows while staying implementation-focused.

      [x] 45.3.1.1 Subtask - Add coverage proving execute workflows can request explicit durable memory context through the product-owned memory workflow boundary.
      [x] 45.3.1.2 Subtask - Add coverage proving the default execute retrieval policy selects implementation-relevant memory and provenance while filtering invalidated entries.
      [x] 45.3.1.3 Subtask - Add coverage proving raw memory queries remain unsupported at the execute workflow boundary.

    [x] 45.3.2 Task - Coder context and degraded-path scenarios
      Prove the coder runtime receives bounded context and that degraded memory states remain explicit and safe.

      [x] 45.3.2.1 Subtask - Add coverage proving `AgentWorkspace.execute_work/4` receives bounded execute memory context and preserves workflow provenance plus follow-up metadata.
      [x] 45.3.2.2 Subtask - Add coverage proving stale, disabled, invalidated, or recovering memory states fail safely and remain explainable for execute callers.
      [x] 45.3.2.3 Subtask - Verify the planning index and memory workflow specs remain coherent after Phase 45 is introduced.
