# Phase 95 - Conversation Runtime Auto-Compaction Adoption

<!-- covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics -->
<!-- covers: architecture.context_management_pod.context_compactor_is_bounded_specialist -->
<!-- covers: architecture.context_management_pod.request_time_budgeting_remains_hard_guard -->
<!-- covers: architecture.context_compaction_policy.compaction_degrades_to_request_time_packing -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-93-automatic-context-compaction-trigger-foundation.md`
- `.planning/phase-94-conversation-context-reset-projection.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/child_worker.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/context_budget.ex`

## Relevant Assumptions / Defaults
- Runtime observations are recorded at progress and completion points.
- Compaction should not interrupt an active turn or leave an assistant/tool-result group half compacted.
- Automatic compaction should run before the next prompt uses older context, not in the middle of provider request assembly.
- Request-time `ContextBudget` packing remains the final guard after any automatic reset.

[ ] 95 Phase 95 - Conversation Runtime Auto-Compaction Adoption
  Wire automatic compaction into the real conversation runtime so threshold-crossing conversations compact and reset before the next turn consumes stale oversized context.

  [x] 95.1 Section - Coordinator Scheduling And Deferral
    Let the conversation coordinator react to monitor recommendations while preserving turn lifecycle ordering.

    [x] 95.1.1 Task - Detect recommendations in runtime payloads
      Inspect runtime progress, delta, needs-input, and completed payloads for context-management decisions.

      [x] 95.1.1.1 Subtask - Extract latest monitor decision metadata from payload-level context-management summaries.
      [x] 95.1.1.2 Subtask - Mark compaction pending when a recommendation appears before the current turn is terminal.
      [x] 95.1.1.3 Subtask - Ignore stale recommendations that do not match the active conversation, work item, or workflow scope.

    [x] 95.1.2 Task - Run compaction at safe boundaries
      Execute pending automatic compaction after the current turn settles and before activating queued work.

      [x] 95.1.2.1 Subtask - Trigger compaction after terminal child-work settlement when the latest recommendation is still eligible.
      [x] 95.1.2.2 Subtask - Defer compaction while a turn is running, awaiting input, cancelling, or superseding.
      [x] 95.1.2.3 Subtask - Ensure queued next turns see reset-aware `shared_context` and active compaction summaries.

  [x] 95.2 Section - Prompt Continuity After Reset
    Ensure future provider requests receive the accepted summary instead of reset-covered raw context.

    [x] 95.2.1 Task - Inject summaries across conversation runtime paths
      Align direct AgentWorkspace, semantic workflow, memory workflow, and fallback paths on the same active summary behavior.

      [x] 95.2.1.1 Subtask - Confirm AgentWorkspace specialist prompts include active summaries after automatic compaction.
      [x] 95.2.1.2 Subtask - Add runtime instruction support for active summary metadata when conversation-owned prompt assembly needs it.
      [x] 95.2.1.3 Subtask - Keep compaction summaries trim/drop eligible under `ContextBudget` and never mark them as required context.

    [x] 95.2.2 Task - Keep required context fresh
      Preserve current request, governed scope, active files, and operator clarification state after the reset.

      [x] 95.2.2.1 Subtask - Confirm the current turn instruction is never sourced from compacted context.
      [x] 95.2.2.2 Subtask - Confirm referenced files can be reintroduced by new turns after a reset.
      [x] 95.2.2.3 Subtask - Confirm prompt memory and durable memory adoption boundaries are unaffected by compaction.

  [x] 95.3 Section - Failure, Concurrency, And Backpressure
    Make automatic compaction safe under compactor errors, racing turns, and repeated threshold crossings.

    [x] 95.3.1 Task - Degrade failed compaction safely
      Preserve existing conversation execution when automatic compaction cannot produce a summary.

      [x] 95.3.1.1 Subtask - Record failed automatic compaction in context-management metadata and conversation lifecycle events.
      [x] 95.3.1.2 Subtask - Continue with request-time packing when compaction fails.
      [x] 95.3.1.3 Subtask - Avoid retry loops until a new recommendation, new source span, or explicit operator retry arrives.

    [x] 95.3.2 Task - Serialize automatic compaction per conversation
      Prevent overlapping compaction attempts from racing with turn admission or reset projection.

      [x] 95.3.2.1 Subtask - Track pending and in-flight compaction state in coordinator runtime state.
      [x] 95.3.2.2 Subtask - Ensure only one compaction attempt runs per conversation at a time.
      [x] 95.3.2.3 Subtask - Preserve stop, pause, steer, and cancellation semantics while compaction is pending.

  [ ] 95.4 Section - Integration Tests
    Prove real conversation turns automatically compact at safe boundaries and continue with bounded prompt context.

    [ ] 95.4.1 Task - Add end-to-end auto-compaction coverage
      Exercise a conversation that crosses the configured high-water threshold and then continues through a new turn.

      [ ] 95.4.1.1 Subtask - Add coverage proving automatic compaction runs after a terminal turn recommendation.
      [ ] 95.4.1.2 Subtask - Add coverage proving the next turn sees active summary metadata and not reset-covered raw accepted tool results.
      [ ] 95.4.1.3 Subtask - Add coverage proving request-time budget packing still runs after automatic compaction.

    [ ] 95.4.2 Task - Add deferral and failure coverage
      Exercise active-turn, awaiting-input, failed-compaction, and repeated-recommendation scenarios.

      [ ] 95.4.2.1 Subtask - Add coverage proving running and awaiting-input turns defer automatic compaction.
      [ ] 95.4.2.2 Subtask - Add coverage proving compactor failure records diagnostics and continues with request-time packing.
      [ ] 95.4.2.3 Subtask - Run conversation runtime, coordinator, context-management, and context-budget focused tests.
