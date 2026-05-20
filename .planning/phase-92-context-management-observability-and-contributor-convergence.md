# Phase 92 - Context Management Observability And Contributor Convergence

<!-- covers: architecture.context_management_pod.context_lifecycle_is_observable -->
<!-- covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata -->
<!-- covers: architecture.context_compaction_policy.compaction_degrades_to_request_time_packing -->
<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-89-context-management-pod-foundation.md`
- `.planning/phase-90-budget-monitor-runtime-adoption.md`
- `.planning/phase-91-context-compactor-summary-lifecycle.md`
- `decisions/jido_code.context_management_pod_and_compaction.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `lib/jido_code/conversations/snapshot.ex`
- `lib/jido_code/agent_workspace.ex`
- `docs/developer/04-coding-pod-and-specialist-workflows.md`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `docs/developer/10-development-workflow-and-quality-gates.md`
- `docs/developer/12-user-request-to-llm-message-path.md`

## Relevant Assumptions / Defaults
- Phases 89 through 91 introduce the pod, monitor, compactor, and summary lifecycle.
- Operators need to know whether compaction is healthy, skipped, degraded, or failed.
- Contributor guidance must keep compaction, prompt memory, durable memory, workflow provenance, and request-time budgeting distinct.
- Failed compaction must degrade to existing request-time packing.

[ ] 92 Phase 92 - Context Management Observability And Contributor Convergence
  Make proactive context management visible, configurable, documented, and covered by quality gates without exposing raw prompt or tool-output dumps.

  [x] 92.1 Section - Runtime Observability And Product Metadata
    Surface context-management state where contributors and operators already inspect runtime behavior.

    [x] 92.1.1 Task - Add context-management summaries to runtime metadata
      Expose concise lifecycle state without turning compaction internals into a transcript browser.

      [x] 92.1.1.1 Subtask - Add latest monitor decision and compaction state to conversation snapshots.
      [x] 92.1.1.2 Subtask - Add compaction summary ids and source span counts to specialist result metadata.
      [x] 92.1.1.3 Subtask - Keep raw source messages and raw tool output out of events, snapshots, and operator surfaces.

    [x] 92.1.2 Task - Capture provenance-safe lifecycle evidence
      Preserve enough evidence to debug compaction behavior without adopting summaries as durable memory.

      [x] 92.1.2.1 Subtask - Record monitor recommendations and compaction outcomes as workflow-provenance metadata.
      [x] 92.1.2.2 Subtask - Link lifecycle evidence to governed work item, conversation id, specialist role, and policy id.
      [x] 92.1.2.3 Subtask - Keep durable-memory adoption behind the existing explicit governed memory boundary.

  [x] 92.2 Section - Configuration And Degraded Recovery
    Make context management tunable and safe under failed monitor, compactor, or summary-store conditions.

    [x] 92.2.1 Task - Add runtime configuration controls
      Expose conservative defaults and environment overrides for proactive context management.

      [x] 92.2.1.1 Subtask - Add config for enablement, high-water marks, repeated-trim thresholds, debounce windows, and summary size limits.
      [x] 92.2.1.2 Subtask - Add local-development env overrides with validation diagnostics.
      [x] 92.2.1.3 Subtask - Add deterministic test overrides for monitor and compactor behavior.

    [x] 92.2.2 Task - Define degraded recovery behavior
      Keep active coding work moving when context management cannot run.

      [x] 92.2.2.1 Subtask - Degrade monitor failures to request-time packing only.
      [x] 92.2.2.2 Subtask - Degrade compactor failures to skipped summary injection with remediation metadata.
      [x] 92.2.2.3 Subtask - Add retry behavior for operator-requested compaction after narrowing context or changing model selection.

  [ ] 92.3 Section - Developer Guides And Quality Gates
    Converge docs so contributors can reason about proactive compaction and existing budget boundaries.

    [ ] 92.3.1 Task - Update architecture guides
      Explain the final context lifecycle from user request through monitoring, compaction, prompt assembly, and provider request.

      [ ] 92.3.1.1 Subtask - Update CodingPod docs with context-management pod topology and ownership.
      [ ] 92.3.1.2 Subtask - Update specialist prompt docs with monitor, compactor, summary injection, and request-time budget guard behavior.
      [ ] 92.3.1.3 Subtask - Update user-request-to-LLM docs with compaction failure modes and debugging order.

    [ ] 92.3.2 Task - Add quality-gate guidance
      Make the correct verification commands discoverable for context-management work.

      [ ] 92.3.2.1 Subtask - Add focused context-management test commands to the quality-gates guide.
      [ ] 92.3.2.2 Subtask - Explain when to run context budget, AgentWorkspace, conversation runtime, source graph, and memory graph verification.
      [ ] 92.3.2.3 Subtask - Update `.planning/README.md` chronology notes for the Phase 89 through Phase 92 track.

  [ ] 92.4 Section - Integration Tests
    End the track with cross-boundary tests proving proactive compaction is observable, recoverable, and still guarded by request-time budgeting.

    [ ] 92.4.1 Task - Add end-to-end context-management coverage
      Exercise monitor recommendation, compactor summary creation, prompt summary injection, and degraded fallback in realistic workflows.

      [ ] 92.4.1.1 Subtask - Add coverage proving repeated trims lead to a compaction summary that appears as bounded prompt context.
      [ ] 92.4.1.2 Subtask - Add coverage proving failed compaction falls back to request-time packing.
      [ ] 92.4.1.3 Subtask - Add coverage proving observability metadata contains ids and diagnostics but no raw prompt dumps.

    [ ] 92.4.2 Task - Run final context-management verification
      Verify the completed rollout across all touched boundaries.

      [ ] 92.4.2.1 Subtask - Run focused Phase 89 through Phase 92 integration tests.
      [ ] 92.4.2.2 Subtask - Run context budget and AgentWorkspace regression tests.
      [ ] 92.4.2.3 Subtask - Run conversation routing and snapshot tests.
      [ ] 92.4.2.4 Subtask - Run `mix source_graph.verify` and `mix memory.verify` if graph prompt projection, provenance, or memory boundaries are touched.
