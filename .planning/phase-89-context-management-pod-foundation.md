# Phase 89 - Context Management Pod Foundation

<!-- covers: architecture.context_management_pod.coding_pod_owns_context_management -->
<!-- covers: architecture.context_management_pod.compaction_store_is_product_owned -->
<!-- covers: architecture.context_management_pod.request_time_budgeting_remains_hard_guard -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `decisions/jido_code.context_management_pod_and_compaction.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agents/coding_pod.ex`
- `lib/jido_code/context_budget.ex`
- `lib/jido_code/context_budget/react_request_transformer.ex`
- `lib/jido_code/agent_workspace/runtime_specialist_runner.ex`
- `docs/developer/04-coding-pod-and-specialist-workflows.md`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `test/jido_code/agent_workspace_test.exs`
- `test/jido_code/context_budget_test.exs`

## Relevant Assumptions / Defaults
- Context management is work-item-scoped because specialist `AIContext` is work-item and specialist-local.
- Request-time `ContextBudget` packing remains mandatory even when proactive compaction exists.
- The first implementation may store compaction summaries in runtime/product state before any durable graph integration is considered.
- Compaction summaries are prompt context, not durable repository memory.

[ ] 89 Phase 89 - Context Management Pod Foundation
  Establish the CodingPod-owned context-management topology and deterministic storage boundary before adding proactive monitoring or AI-backed compaction.

  [x] 89.1 Section - Pod Topology And Ownership Contracts
    Define where context management lives in the AgentOS runtime and how other specialists address it.

    [x] 89.1.1 Task - Define the `ContextManagementPod` runtime shape
      Add the pod contract as a work-item-scoped CodingPod child so context state cannot bleed across governed work.

      [x] 89.1.1.1 Subtask - Define the pod id, metadata shape, and lifecycle relationship to `CodingPod`.
      [x] 89.1.1.2 Subtask - Define child agent names for `BudgetMonitor`, `ContextCompactor`, and deterministic store access.
      [x] 89.1.1.3 Subtask - Document that repository-scoped pods may observe aggregate health but cannot own specialist history compaction.

    [x] 89.1.2 Task - Add product-owned API seams
      Introduce entrypoints that let `AgentWorkspace` and specialist runners interact with context management without knowing internal agent details.

      [x] 89.1.2.1 Subtask - Add ensure/get/shutdown helpers for the context-management pod under the same managed-repo kernel as `CodingPod`.
      [x] 89.1.2.2 Subtask - Define request and response structs for budget observations, compaction recommendations, and compaction summaries.
      [x] 89.1.2.3 Subtask - Keep all public entrypoints scoped by `managed_repo_id`, `work_item_id`, and specialist role.

  [x] 89.2 Section - Compaction Store And Summary Data Model
    Add a deterministic store boundary for summaries and replacement metadata before any LLM compactor writes are accepted.

    [x] 89.2.1 Task - Model compaction summaries
      Define the summary record shape that can be safely reused as bounded prompt context.

      [x] 89.2.1.1 Subtask - Include summary id, workflow, specialist role, work item id, source span identifiers, and token estimates.
      [x] 89.2.1.2 Subtask - Include summary text, retention class, created-at timestamp, policy id, and diagnostics.
      [x] 89.2.1.3 Subtask - Reject records that contain raw prompt bodies or raw tool output in diagnostics.

    [x] 89.2.2 Task - Define replacement metadata
      Track what older context a summary replaces without mutating conversation history or workflow provenance.

      [x] 89.2.2.1 Subtask - Store source message ids or stable span keys separate from summary text.
      [x] 89.2.2.2 Subtask - Mark summaries superseded when a newer summary covers the same span.
      [x] 89.2.2.3 Subtask - Keep original durable conversation events and provenance records append-only.

  [ ] 89.3 Section - Request-Time Guard Preservation
    Make the new topology explicitly additive so the existing request-time budget guard remains the final provider boundary.

    [ ] 89.3.1 Task - Preserve `ContextBudget` as the hard safety net
      Ensure every specialist request still flows through request-time packing regardless of proactive compaction state.

      [ ] 89.3.1.1 Subtask - Keep `JidoCode.ContextBudget.ReActRequestTransformer` installed by default for CodingPod specialists.
      [ ] 89.3.1.2 Subtask - Add tests proving disabled context management still sends packed provider requests.
      [ ] 89.3.1.3 Subtask - Add diagnostics that identify proactive compaction as skipped, unavailable, or healthy without changing provider safety.

    [ ] 89.3.2 Task - Add feature configuration
      Expose conservative controls for enabling, disabling, and tuning the new pod.

      [ ] 89.3.2.1 Subtask - Add runtime config for context-management enablement and default thresholds.
      [ ] 89.3.2.2 Subtask - Add per-request override hooks for tests and explicit operator workflows.
      [ ] 89.3.2.3 Subtask - Validate invalid config as degraded context-management configuration rather than disabling request-time budgeting.

  [ ] 89.4 Section - Integration Tests
    Prove the pod topology can be created, addressed, disabled, and degraded without affecting existing specialist execution.

    [ ] 89.4.1 Task - Add topology and fallback coverage
      Exercise the new pod lifecycle through real AgentWorkspace setup paths.

      [ ] 89.4.1.1 Subtask - Add coverage proving each CodingPod owns one context-management pod per work item.
      [ ] 89.4.1.2 Subtask - Add coverage proving different work items do not share compaction store state.
      [ ] 89.4.1.3 Subtask - Add coverage proving disabled context management leaves request-time budget packing intact.

    [ ] 89.4.2 Task - Run foundation verification
      Verify the new topology with existing AgentWorkspace and context-budget gates.

      [ ] 89.4.2.1 Subtask - Run focused context budget tests.
      [ ] 89.4.2.2 Subtask - Run `mix test test/jido_code/agent_workspace_test.exs --max-cases 1 --max-failures 1`.
      [ ] 89.4.2.3 Subtask - Run any additional AgentOS pod lifecycle tests added in this phase.
