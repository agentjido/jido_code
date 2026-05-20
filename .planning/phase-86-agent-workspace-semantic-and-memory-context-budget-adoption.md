# Phase 86 - AgentWorkspace Semantic And Memory Context Budget Adoption

<!-- covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context -->
<!-- covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_context -->
<!-- covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-85-context-budget-policy-and-prompt-packing-foundation.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/source_code_graph/workflow_service.ex`
- `lib/jido_code/memory_graph/workflow_service.ex`
- `lib/jido_code/memory_graph/retrieval_policy.ex`
- `lib/jido_code/conversations/runtime.ex`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `docs/developer/07-source-code-graph-and-semantic-services.md`
- `docs/developer/08-memory-graph-and-workflow-provenance.md`
- `docs/developer/12-user-request-to-llm-message-path.md`
- `test/jido_code/source_code_graph_workflow_service_test.exs`
- `test/jido_code/memory_graph_workflow_service_test.exs`
- `test/jido_code/agent_workspace_test.exs`

## Relevant Assumptions / Defaults
- Phase 85 introduces a product-owned context budget policy and prompt-packing service.
- `AgentWorkspace` currently renders semantic and memory context with unbounded `inspect(..., limit: :infinity)` when those contexts are present.
- Structured `tool_context` can remain richer than prompt-facing text because tools consume it out-of-band.
- Semantic and memory graph contexts are enhancements; specialist execution must remain legible when they are trimmed, stale, degraded, or unavailable.

[ ] 86 Phase 86 - AgentWorkspace Semantic And Memory Context Budget Adoption
  Adopt context budgeting at the workspace specialist boundary so semantic and memory context enter prompts as compact, budgeted projections instead of raw unbounded maps.

  [x] 86.1 Section - Prompt-Facing Semantic And Memory Projection Contracts
    Define compact context shapes for prompt text while preserving richer graph state in `tool_context`.

    [x] 86.1.1 Task - Add semantic prompt projection shaping
      Convert source-code graph workflow output into section-ready summaries sized for prompt use.

      [x] 86.1.1.1 Subtask - Define prompt-facing semantic fields for graph readiness, revision, selected modules/functions, findings, and degraded-state notes.
      [x] 86.1.1.2 Subtask - Cap semantic projection item counts and per-item text before the packer receives the section.
      [x] 86.1.1.3 Subtask - Preserve full graph status and query context in `tool_context` where tools need structured data.

    [x] 86.1.2 Task - Add memory prompt projection shaping
      Convert memory workflow context into compact prompt sections that do not expose raw graph internals.

      [x] 86.1.2.1 Subtask - Define prompt-facing memory fields for freshness, retrieval policy, selected memories, selected provenance, conversation recall, and governed references.
      [x] 86.1.2.2 Subtask - Apply existing retrieval-policy limits before prompt packing and add per-item byte caps for selected items.
      [x] 86.1.2.3 Subtask - Preserve structured memory graph context in `tool_context` without treating it as automatically prompt-visible.

  [x] 86.2 Section - AgentWorkspace Prompt Packing Adoption
    Replace unbounded prompt rendering in specialist instructions with Phase 85 section packing.

    [x] 86.2.1 Task - Pack specialist instructions with semantic and memory sections
      Ensure `plan_work/3,4`, `execute_work/3,4`, `review_work/3,4`, `refactor_work/3,4`, and explain paths use the same budgeted instruction contract.

      [x] 86.2.1.1 Subtask - Replace raw `inspect(..., limit: :infinity)` prompt sections with budgeted semantic and memory sections.
      [x] 86.2.1.2 Subtask - Preserve the raw operator instruction as required context when semantic or memory sections are trimmed.
      [x] 86.2.1.3 Subtask - Carry packing diagnostics into specialist run metadata and workflow provenance capture.

    [x] 86.2.2 Task - Keep tool context structured and non-prompt by default
      Maintain the distinction between prompt text and request-scoped tool execution data.

      [x] 86.2.2.1 Subtask - Keep `managed_repo_id`, `workspace_path`, graph status, and memory graph context available to tools through `tool_context`.
      [x] 86.2.2.2 Subtask - Avoid duplicating large structured `tool_context` values into prompt sections unless explicitly projected.
      [x] 86.2.2.3 Subtask - Add diagnostics that show prompt context was trimmed without implying tool context was lost.

  [x] 86.3 Section - Workflow Consistency And Degraded States
    Make budgeted semantic and memory context behave consistently across specialist workflows and fallback paths.

    [x] 86.3.1 Task - Align workflow-specific context selection
      Preserve the current workflow routing behavior while making context size management explicit.

      [x] 86.3.1.1 Subtask - Keep execute and refactor workflows preferring memory context when memory workflows are enabled.
      [x] 86.3.1.2 Subtask - Keep plan, review, and explain workflows preferring semantic context when source graph workflows are enabled.
      [x] 86.3.1.3 Subtask - Ensure budget diagnostics explain whether context was missing, degraded, stale, trimmed, or fully packed.

    [x] 86.3.2 Task - Preserve governed memory and semantic product boundaries
      Keep compact prompt context from becoming a substitute for governed records, graph truth, or durable memory adoption.

      [x] 86.3.2.1 Subtask - Keep semantic findings and memory findings as governed product records before they influence durable product behavior.
      [x] 86.3.2.2 Subtask - Keep prompt-facing memory projections separate from durable memory graph writes.
      [x] 86.3.2.3 Subtask - Update developer docs to distinguish prompt projection, `tool_context`, workflow provenance, and durable graph state.

  [ ] 86.4 Section - Integration Tests
    Prove workspace specialist prompts stay within budget while graph-backed workflow context remains useful and structured tools still receive full request context.

    [ ] 86.4.1 Task - Add workspace prompt-packing integration coverage
      Exercise each specialist entrypoint with oversized semantic and memory context.

      [ ] 86.4.1.1 Subtask - Add coverage proving semantic context is compacted before prompt injection.
      [ ] 86.4.1.2 Subtask - Add coverage proving memory context is compacted before prompt injection.
      [ ] 86.4.1.3 Subtask - Add coverage proving `tool_context` still contains structured graph and workspace fields after prompt trimming.

    [ ] 86.4.2 Task - Run semantic, memory, and workspace verification gates
      Verify the adoption across the graph workflow and specialist boundaries.

      [ ] 86.4.2.1 Subtask - Run focused `AgentWorkspace` specialist prompt tests.
      [ ] 86.4.2.2 Subtask - Run `mix source_graph.verify` if semantic workflow projections are touched.
      [ ] 86.4.2.3 Subtask - Run `mix memory.verify` if memory workflow projections are touched.
      [ ] 86.4.2.4 Subtask - Run conversation routing integration tests that exercise execute, refactor, review, and explain context paths.
