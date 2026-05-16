# Phase 83 - Refactorer Conversation Routing Adoption

<!-- covers: architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned -->
<!-- covers: architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence -->
<!-- covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `lib/jido_code/conversations/workflow_router.ex`
- `lib/jido_code/conversations/work_resolution.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/driver.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agents/refactorer.ex`
- `docs/developer/04-coding-pod-and-specialist-workflows.md`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `docs/developer/12-user-request-to-llm-message-path.md`
- `test/jido_code/conversations_driver_test.exs`
- `test/jido_code/conversations_coordinator_test.exs`
- `test/jido_code/agent_workspace_test.exs`

## Relevant Assumptions / Defaults
- Phase 81 exposes `AgentWorkspace.refactor_work/3,4` as the product-owned API for the lazy `Refactorer` specialist.
- Conversation workflow routing currently treats the canonical productive workflows as `:plan`, `:execute`, `:review`, and `:explain`.
- `full_workflow/3,4` remains plan -> execute -> review; this phase adopts conversation routing only and should not silently add refactor to full workflow orchestration.
- Refactor routing should be deterministic and explicit enough that generic edit, fix, or patch requests still route to `:execute` unless the operator's intent is behavior-preserving refactoring.

## Implementation Notes
- Phase 83.1 adds `:refactor` to `WorkflowRouter.workflows/0`, normalization, default scores, metadata, and deterministic cues for explicit behavior-preserving refactor intent.
- Execute routing keeps generic implementation, fix, edit, update, and patch cues; refactor-specific scoring is separated so broad implementation requests do not silently move to the Refactorer.
- Phase 83.2 routes refactor runtime requests through `AgentWorkspace.refactor_work/4`, projects `:refactoring` results, includes refactor in governed work resolution, and adds refactor-aware memory workflow policy.
- Phase 83.3 updates developer guidance and current-truth notes so conversation-level refactor routing is discoverable while `full_workflow/3,4` remains plan -> execute -> review.
- Phase 83.4 adds focused router, conversation runtime, work-item identity, and memory workflow coverage for refactor routing.
- Verified with the Phase 83 integration test, Phase 52 routing regression test, conversation-runtime batch, AgentWorkspace tests, memory workflow service tests, and `mix memory.verify`.

[x] 83 Phase 83 - Refactorer Conversation Routing Adoption
  Adopt the existing Refactorer specialist into deterministic conversation workflow routing so explicit behavior-preserving refactor requests reach `AgentWorkspace.refactor_work/3,4` without weakening execute, review, explain, or full-workflow semantics.

  [x] 83.1 Section - Routing Model And Intent Contract
    Extend the canonical workflow routing model with refactor intent while keeping routing explainable and bounded.

    [x] 83.1.1 Task - Add `:refactor` to the canonical workflow router
      Teach the product-owned routing boundary that refactor is a valid specialist workflow with its own scoring, metadata, and normalization path.

      [x] 83.1.1.1 Subtask - Extend workflow normalization, workflow lists, and routing metadata to include `:refactor`.
      [x] 83.1.1.2 Subtask - Add deterministic refactor cues such as "refactor", "extract", "rename", "simplify", and "preserve behavior" without stealing generic implementation requests from `:execute`.
      [x] 83.1.1.3 Subtask - Keep routing reasons inspectable so operators and tests can distinguish explicit refactor intent from implementation or review intent.

    [x] 83.1.2 Task - Preserve routing precedence and ambiguity behavior
      Make refactor adoption follow the same explicit intent, continuity, and clarification rules established by deterministic workflow routing.

      [x] 83.1.2.1 Subtask - Let explicit product intent select `:refactor` ahead of free-text cues.
      [x] 83.1.2.2 Subtask - Preserve active work-item workflow continuity for refactor turns unless the operator explicitly changes workflow.
      [x] 83.1.2.3 Subtask - Clarify ambiguous requests when refactor and execute or review signals are tied or weak.

  [x] 83.2 Section - Runtime Dispatch And Result Projection
    Route refactor decisions through the same conversation runtime, governed work, and workspace boundaries as other productive workflows.

    [x] 83.2.1 Task - Dispatch refactor workflow through `AgentWorkspace.refactor_work/4`
      Make the conversation runtime call the public workspace refactor API rather than addressing the pod or specialist directly.

      [x] 83.2.1.1 Subtask - Add runtime dispatch for `:refactor` that passes managed repo id, work item id, bounded instruction, workspace path, LLM selection, semantic context, memory context, and provenance options.
      [x] 83.2.1.2 Subtask - Preserve typed unavailable or degraded states when workspace path, CodingPod runtime, graph context, or specialist execution cannot run.
      [x] 83.2.1.3 Subtask - Ensure refactor runtime results project the `:refactoring` payload into conversation output without disrupting existing plan, execute, review, and explain projections.

    [x] 83.2.2 Task - Align governed work resolution with refactor conversations
      Keep work-item identity and admission rules coherent when a conversation turn requests behavior-preserving refactoring.

      [x] 83.2.2.1 Subtask - Include `:refactor` in productive work-resolution workflows that require governed work attachment.
      [x] 83.2.2.2 Subtask - Preserve one active productive conversation per WorkItem and allow parallel refactor conversations across different work items.
      [x] 83.2.2.3 Subtask - Keep refactor conversation provenance and prompt-memory behavior bounded by the same work-item scope as other specialist workflows.

  [x] 83.3 Section - Surface Guidance And Current-Truth Convergence
    Make refactor routing understandable to operators and contributors while preserving the current product-owned boundaries.

    [x] 83.3.1 Task - Update developer guidance for conversation-level refactor routing
      Align docs with the new workflow path so future contributors know when to use refactor instead of execute.

      [x] 83.3.1.1 Subtask - Update the user-request-to-LLM path guide to list `:refactor` as a conversation-routed workflow once implemented.
      [x] 83.3.1.2 Subtask - Update CodingPod and specialist prompt guides to distinguish workspace API exposure from conversation runtime adoption.
      [x] 83.3.1.3 Subtask - Document that `full_workflow/3,4` still remains plan -> execute -> review unless a later phase changes that orchestration contract.

    [x] 83.3.2 Task - Update product-facing routing metadata and degraded states
      Keep refactor workflow status observable and typed at the same level as other conversation workflows.

      [x] 83.3.2.1 Subtask - Include refactor workflow names and labels wherever conversation workflow metadata is surfaced to operators.
      [x] 83.3.2.2 Subtask - Preserve route-owned recovery copy when refactor routing cannot start because runtime, workspace, or graph context is unavailable.
      [x] 83.3.2.3 Subtask - Keep product surfaces from exposing pod-local details such as node names, process ids, or specialist internals.

  [x] 83.4 Section - Integration Tests
    End the phase by proving explicit refactor conversations route through the Refactorer while existing workflows keep their current behavior.

    [x] 83.4.1 Task - Add focused routing and runtime coverage
      Verify `:refactor` is selected, dispatched, and projected only when routing inputs justify it.

      [x] 83.4.1.1 Subtask - Add coverage proving explicit refactor intent routes to `:refactor` and invokes `AgentWorkspace.refactor_work/4`.
      [x] 83.4.1.2 Subtask - Add coverage proving generic fix, edit, and implementation requests still route to `:execute`.
      [x] 83.4.1.3 Subtask - Add coverage proving ambiguous execute/refactor or review/refactor requests clarify rather than silently choosing the wrong specialist.

    [x] 83.4.2 Task - Add end-to-end conversation coverage
      Verify refactor routing behaves correctly through governed work-item conversations and existing runtime context boundaries.

      [x] 83.4.2.1 Subtask - Add an end-to-end conversation test that creates or reuses governed work and records a refactor turn result.
      [x] 83.4.2.2 Subtask - Add coverage proving refactor turns preserve work-item conversation identity and do not allow a second active conversation for the same WorkItem.
      [x] 83.4.2.3 Subtask - Run the conversation-runtime suite, AgentWorkspace refactor coverage, and any memory or semantic verification commands required by touched boundaries.
