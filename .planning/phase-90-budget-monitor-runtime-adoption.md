# Phase 90 - Budget Monitor Runtime Adoption

<!-- covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics -->
<!-- covers: architecture.context_compaction_policy.compaction_is_threshold_driven -->
<!-- covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-89-context-management-pod-foundation.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `lib/jido_code/context_budget.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_workspace/runtime_specialist_runner.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/snapshot.ex`
- `test/jido_code/phase_eighty_eight_integration_test.exs`

## Relevant Assumptions / Defaults
- Phase 89 introduces the context-management pod and deterministic store boundary.
- Budget monitoring must consume structured diagnostics, not raw prompt text.
- Monitor decisions are recommendations until Phase 91 adds actual summary compaction.
- Repeated-trim and high-water triggers should be deterministic and debounced.

[ ] 90 Phase 90 - Budget Monitor Runtime Adoption
  Wire context-budget diagnostics into a work-item-scoped `BudgetMonitor` that can recommend compaction without mutating specialist history.

  [x] 90.1 Section - Budget Observation Ingestion
    Connect existing budget diagnostics to the monitor through explicit runtime signals or product-owned calls.

    [x] 90.1.1 Task - Capture specialist budget observations
      Feed prompt, history, and tool-output diagnostics into the monitor after specialist runs.

      [x] 90.1.1.1 Subtask - Capture context-budget summaries from AgentWorkspace specialist results.
      [x] 90.1.1.2 Subtask - Capture ReAct history packing diagnostics from request transformer output or runner metadata.
      [x] 90.1.1.3 Subtask - Capture tool-output truncation diagnostics from workspace actions without storing raw tool output.

    [x] 90.1.2 Task - Capture conversation-runtime budget observations
      Let conversation turns contribute budget state when runtime instruction packing trims optional context.

      [x] 90.1.2.1 Subtask - Feed runtime progress context-budget summaries into the monitor when a turn is attached to a work item.
      [x] 90.1.2.2 Subtask - Link observations to conversation id, turn id, workflow, work item id, and specialist role when known.
      [x] 90.1.2.3 Subtask - Ignore repo-scoped nonproductive turns that do not have governed work-item context.

  [ ] 90.2 Section - Threshold Policy And Recommendations
    Implement deterministic monitor policy that decides when compaction is useful and when it is unsafe.

    [ ] 90.2.1 Task - Add trigger evaluation
      Convert accumulated observations into explicit no-op, recommend, or blocked decisions.

      [ ] 90.2.1.1 Subtask - Add high-water mark checks for retained history token estimates.
      [ ] 90.2.1.2 Subtask - Add repeated-trim checks for conversation history and optional context sections.
      [ ] 90.2.1.3 Subtask - Add debounce keys so unchanged spans do not generate duplicate compaction recommendations.

    [ ] 90.2.2 Task - Add safety checks
      Prevent compaction recommendations when active context is not safe to summarize.

      [ ] 90.2.2.1 Subtask - Block recommendations while a tool-call group is unresolved.
      [ ] 90.2.2.2 Subtask - Block recommendations when only required context exceeds budget.
      [ ] 90.2.2.3 Subtask - Emit clear degraded diagnostics when compaction is unsafe or unavailable.

  [ ] 90.3 Section - Monitor Diagnostics And Product Metadata
    Make monitor decisions visible without leaking raw prompt bodies or tool output.

    [ ] 90.3.1 Task - Surface monitor state
      Add concise monitor state to the same surfaces that already expose context-budget diagnostics.

      [ ] 90.3.1.1 Subtask - Add monitor state to context-management pod metadata.
      [ ] 90.3.1.2 Subtask - Add latest recommendation summaries to conversation snapshots when attached to work-item context.
      [ ] 90.3.1.3 Subtask - Add provenance-safe metadata for observations and recommendations.

    [ ] 90.3.2 Task - Keep diagnostics metadata-only
      Enforce the rule that monitor records never become transcript or tool-output storage.

      [ ] 90.3.2.1 Subtask - Add redaction or validation around monitor observation payloads.
      [ ] 90.3.2.2 Subtask - Add tests proving prompt sentinels do not appear in monitor metadata.
      [ ] 90.3.2.3 Subtask - Document monitor diagnostics in developer guides.

  [ ] 90.4 Section - Integration Tests
    Prove the monitor recommends compaction deterministically and safely based on structured budget diagnostics.

    [ ] 90.4.1 Task - Add monitor decision coverage
      Exercise high-water, repeated-trim, no-op, and blocked recommendation paths.

      [ ] 90.4.1.1 Subtask - Add tests proving repeated history trimming produces one debounced recommendation.
      [ ] 90.4.1.2 Subtask - Add tests proving required-section overflow is reported as degraded rather than compaction-ready.
      [ ] 90.4.1.3 Subtask - Add tests proving unresolved tool-call groups block recommendations.

    [ ] 90.4.2 Task - Run monitor verification
      Verify monitor integration across runtime, specialist, and conversation metadata paths.

      [ ] 90.4.2.1 Subtask - Run focused context-management monitor tests.
      [ ] 90.4.2.2 Subtask - Run Phase 88 context-budget observability tests.
      [ ] 90.4.2.3 Subtask - Run conversation snapshot and AgentWorkspace tests touched by monitor integration.
