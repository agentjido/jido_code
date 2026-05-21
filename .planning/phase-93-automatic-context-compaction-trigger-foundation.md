# Phase 93 - Automatic Context Compaction Trigger Foundation

<!-- covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics -->
<!-- covers: architecture.context_compaction_policy.compaction_is_threshold_driven -->
<!-- covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-89-context-management-pod-foundation.md`
- `.planning/phase-90-budget-monitor-runtime-adoption.md`
- `.planning/phase-91-context-compactor-summary-lifecycle.md`
- `.planning/phase-92-context-management-observability-and-contributor-convergence.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `lib/jido_code/context_management.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/snapshot.ex`

## Relevant Assumptions / Defaults
- Phase 90 monitor decisions currently recommend compaction but do not automatically run it.
- Phase 91 exposes `AgentWorkspace.compact_context/4` and deterministic candidate compaction.
- Automatic compaction must remain product-owned; `BudgetMonitor` should decide, not mutate conversation or specialist history directly.
- The first automatic implementation should compact only protocol-safe older conversation context and should degrade to request-time packing.

[x] 93 Phase 93 - Automatic Context Compaction Trigger Foundation
  Establish the product-owned bridge from budget-monitor recommendations to safe compaction candidates without mutating conversation history or blocking active work.

  [x] 93.1 Section - Recommendation-To-Action Contract
    Define when a monitor recommendation becomes an automatic compaction attempt and when it remains metadata only.

    [x] 93.1.1 Task - Define automatic compaction eligibility
      Add a deterministic policy helper that evaluates context-management status, latest monitor decision, policy configuration, and debounce state.

      [x] 93.1.1.1 Subtask - Treat only `recommend` monitor decisions as auto-compaction candidates.
      [x] 93.1.1.2 Subtask - Skip automatic compaction when context management or compaction is disabled.
      [x] 93.1.1.3 Subtask - Skip debounced, already-compacted, blocked, degraded, or healthy decisions with explicit diagnostics.

    [x] 93.1.2 Task - Add action-oriented monitor output
      Return a compact action result that callers can use without inspecting raw pod metadata.

      [x] 93.1.2.1 Subtask - Add result states for `:compact`, `:skip`, `:defer`, and `:blocked`.
      [x] 93.1.2.2 Subtask - Include recommendation id, debounce key, workflow, specialist role, policy id, conversation id, and turn id.
      [x] 93.1.2.3 Subtask - Keep the action result metadata-only and free of prompt text or tool-output bodies.

  [x] 93.2 Section - Compaction Candidate Source Construction
    Build protocol-safe compaction candidates from conversation runtime state after a recommendation has crossed the configured threshold.

    [x] 93.2.1 Task - Add conversation-to-candidate projection
      Convert older conversation events, turns, and accepted child-work results into `ContextManagement.compaction_candidate/3` input messages.

      [x] 93.2.1.1 Subtask - Map operator/user turns to user messages with stable span ids.
      [x] 93.2.1.2 Subtask - Map completed runtime output and accepted tool results to assistant or tool messages without raw diagnostic storage.
      [x] 93.2.1.3 Subtask - Include workflow, specialist role, work item id, conversation id, turn id, and policy id in candidate attributes.

    [x] 93.2.2 Task - Preserve active and unsafe context
      Ensure automatic candidates do not summarize required scope, active requests, pending clarification, or unresolved tool groups.

      [x] 93.2.2.1 Subtask - Exclude the latest non-system group and any currently running or awaiting-input turn.
      [x] 93.2.2.2 Subtask - Reject candidates that would split assistant/tool-result groups.
      [x] 93.2.2.3 Subtask - Reject candidates that only contain current request, repository scope, pending clarification, or no eligible older context.

  [x] 93.3 Section - Automatic Compaction Execution Boundary
    Introduce an explicit boundary that callers can invoke after a recommendation to compact eligible context and persist the summary.

    [x] 93.3.1 Task - Add a product-owned auto-compaction helper
      Route eligible candidates through `AgentWorkspace.compact_context/4` without exposing compactor internals to the coordinator.

      [x] 93.3.1.1 Subtask - Accept managed repo id, work item id, conversation state or snapshot, latest recommendation metadata, and context-management opts.
      [x] 93.3.1.2 Subtask - Return accepted summary status, skipped diagnostics, deferred diagnostics, or compaction failure details.
      [x] 93.3.1.3 Subtask - Ensure failures call the existing compaction failure persistence path and never mutate raw conversation events.

    [x] 93.3.2 Task - Add idempotency around repeated recommendations
      Prevent automatic compaction loops for unchanged source spans and repeated threshold observations.

      [x] 93.3.2.1 Subtask - Detect an active summary that already covers the same source span ids.
      [x] 93.3.2.2 Subtask - Preserve monitor debounce semantics when the same recommendation is observed repeatedly.
      [x] 93.3.2.3 Subtask - Emit a skipped state that explains idempotent no-op behavior.

  [x] 93.4 Section - Integration Tests
    Prove threshold recommendations can be converted into safe automatic compaction attempts without changing the append-only conversation model.

    [x] 93.4.1 Task - Add automatic trigger coverage
      Exercise the monitor-to-action bridge with high-water, repeated-trim, disabled, debounced, blocked, and ineligible states.

      [x] 93.4.1.1 Subtask - Add tests proving a `recommend` decision produces a `:compact` action when compaction is enabled.
      [x] 93.4.1.2 Subtask - Add tests proving disabled and blocked decisions produce metadata-only skips.
      [x] 93.4.1.3 Subtask - Add tests proving unchanged debounced recommendations do not create duplicate summaries.

    [x] 93.4.2 Task - Add candidate safety coverage
      Verify the automatic candidate builder preserves protocol and active-turn boundaries.

      [x] 93.4.2.1 Subtask - Add coverage for completed older turns plus the active latest turn.
      [x] 93.4.2.2 Subtask - Add coverage proving unresolved tool groups defer or reject automatic compaction.
      [x] 93.4.2.3 Subtask - Run focused context-management and conversation snapshot tests.
