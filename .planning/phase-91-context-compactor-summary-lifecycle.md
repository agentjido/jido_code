# Phase 91 - Context Compactor Summary Lifecycle

<!-- covers: architecture.context_management_pod.context_compactor_is_bounded_specialist -->
<!-- covers: architecture.context_compaction_policy.compaction_preserves_required_context -->
<!-- covers: architecture.context_compaction_policy.tool_protocol_boundaries_are_preserved -->
<!-- covers: architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-89-context-management-pod-foundation.md`
- `.planning/phase-90-budget-monitor-runtime-adoption.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `lib/jido_code/context_budget.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_workspace/prompt_projection.ex`
- `deps/jido_ai/lib/jido_ai/context.ex`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `test/jido_code/context_budget_test.exs`

## Relevant Assumptions / Defaults
- Phase 90 can recommend compaction but does not summarize history.
- Compaction summaries are prompt-context aids, not durable repository memory.
- Compaction candidates must be selected at protocol-safe group boundaries.
- Request-time packing still runs after compaction summary injection.

[x] 91 Phase 91 - Context Compactor Summary Lifecycle
  Add the bounded compaction flow that turns eligible older specialist history into reusable summaries and injects those summaries into later prompts.

  [x] 91.1 Section - Compaction Candidate Selection
    Build deterministic candidate extraction before invoking any AI-backed compactor.

    [x] 91.1.1 Task - Select protocol-safe spans
      Identify older specialist history that can be summarized without breaking ReAct tool-call semantics.

      [x] 91.1.1.1 Subtask - Group assistant tool-call messages with their following tool-result messages.
      [x] 91.1.1.2 Subtask - Exclude current request, system messages, pending clarification, and unresolved tool-call groups.
      [x] 91.1.1.3 Subtask - Produce source span identifiers, estimates, and eligibility diagnostics.

    [x] 91.1.2 Task - Define compaction request shape
      Pass only bounded, eligible context into the compactor with enough metadata to produce traceable summaries.

      [x] 91.1.2.1 Subtask - Include workflow, specialist role, work item id, conversation id, and policy id.
      [x] 91.1.2.2 Subtask - Include bounded source text or a deterministic fixture representation for AI compaction.
      [x] 91.1.2.3 Subtask - Reject candidates that exceed compactor input limits before invoking the model.

  [x] 91.2 Section - ContextCompactor Agent And Summary Validation
    Implement the compactor as a bounded AI-backed specialist with strict output validation.

    [x] 91.2.1 Task - Add compactor agent behavior
      Create the specialist or action boundary that summarizes eligible history into compact prompt context.

      [x] 91.2.1.1 Subtask - Define the compactor system prompt around faithful summarization and explicit uncertainty.
      [x] 91.2.1.2 Subtask - Route compactor calls through existing LLM selection and request-time budget policy.
      [x] 91.2.1.3 Subtask - Ensure compactor failures return diagnostics and do not block the active specialist turn.

    [x] 91.2.2 Task - Validate compaction outputs
      Accept only bounded summaries with required metadata and safe prompt shape.

      [x] 91.2.2.1 Subtask - Validate summary text length, retention class, source span ids, and token estimates.
      [x] 91.2.2.2 Subtask - Reject output that includes raw full tool output or raw transcript dumps.
      [x] 91.2.2.3 Subtask - Store accepted summaries through `CompactionStore` with replacement metadata.

  [x] 91.3 Section - Summary Injection And History Lifecycle
    Reuse accepted summaries in prompt assembly while keeping raw history recoverable only through governed records.

    [x] 91.3.1 Task - Inject summaries as budgeted prompt sections
      Make compacted context available to specialists without bypassing `ContextBudget`.

      [x] 91.3.1.1 Subtask - Add a typed compaction summary section to AgentWorkspace prompt assembly.
      [x] 91.3.1.2 Subtask - Let `ContextBudget` trim or drop compaction summaries like other non-required sections.
      [x] 91.3.1.3 Subtask - Include summary diagnostics in specialist budget metadata.

    [x] 91.3.2 Task - Manage compacted history state
      Avoid repeatedly resending raw old history after a summary supersedes it.

      [x] 91.3.2.1 Subtask - Mark compacted spans as summarized in context-management state.
      [x] 91.3.2.2 Subtask - Prefer summaries over raw eligible spans in future prompt construction.
      [x] 91.3.2.3 Subtask - Preserve original conversation events and workflow provenance as append-only recovery records.

  [x] 91.4 Section - Integration Tests
    Prove compaction produces valid summaries, preserves protocol integrity, and improves prompt continuity without replacing request-time packing.

    [x] 91.4.1 Task - Add compactor lifecycle coverage
      Exercise recommendation to candidate to summary to prompt injection.

      [x] 91.4.1.1 Subtask - Add tests proving old specialist history is summarized and no longer resent raw.
      [x] 91.4.1.2 Subtask - Add tests proving assistant/tool-result groups remain valid after compaction.
      [x] 91.4.1.3 Subtask - Add tests proving compaction summary sections can be trimmed by `ContextBudget`.

    [x] 91.4.2 Task - Run compactor verification
      Verify the lifecycle across context budget, AgentWorkspace, and conversation routing boundaries.

      [x] 91.4.2.1 Subtask - Run focused compactor lifecycle tests.
      [x] 91.4.2.2 Subtask - Run context budget and AgentWorkspace tests.
      [x] 91.4.2.3 Subtask - Run memory verification if provenance or durable-memory boundaries are touched.
