# Phase 96 - Auto-Compaction Observability And Contributor Convergence

<!-- covers: architecture.context_management_pod.context_lifecycle_is_observable -->
<!-- covers: architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory -->
<!-- covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata -->
<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-93-automatic-context-compaction-trigger-foundation.md`
- `.planning/phase-94-conversation-context-reset-projection.md`
- `.planning/phase-95-conversation-runtime-auto-compaction-adoption.md`
- `decisions/jido_code.context_management_pod_and_compaction.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `docs/developer/04-coding-pod-and-specialist-workflows.md`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`
- `docs/developer/10-development-workflow-and-quality-gates.md`
- `docs/developer/12-user-request-to-llm-message-path.md`
- `.planning/README.md`

## Relevant Assumptions / Defaults
- Phases 93 through 95 introduce automatic recommendation handling, reset-aware projections, and runtime adoption.
- Operators and contributors need to distinguish monitor recommendation, attempted compaction, accepted summary, reset marker, skipped compaction, and degraded fallback.
- Automatic compaction remains a prompt-continuity optimization, not durable memory adoption.
- Existing request-time context-budget verification remains mandatory for this track.

[x] 96 Phase 96 - Auto-Compaction Observability And Contributor Convergence
  Make automatic compaction explainable, configurable, documented, and covered by contributor quality gates after runtime adoption lands.

  [x] 96.1 Section - Lifecycle Metadata And Operator Visibility
    Surface the automatic compaction lifecycle without exposing raw reset-covered context.

    [x] 96.1.1 Task - Add auto-compaction lifecycle summaries
      Extend context-management and conversation metadata with concise automatic compaction states.

      [x] 96.1.1.1 Subtask - Surface pending, in-flight, compacted, skipped, deferred, and degraded states.
      [x] 96.1.1.2 Subtask - Include reset sequence, summary ids, source span counts, recommendation ids, and policy ids.
      [x] 96.1.1.3 Subtask - Keep raw old messages, raw tool outputs, and prompt bodies out of snapshots and operator metadata.

    [x] 96.1.2 Task - Add debugging breadcrumbs
      Provide enough structured evidence to diagnose automatic compaction behavior from normal product surfaces.

      [x] 96.1.2.1 Subtask - Link monitor decisions to compaction attempts and reset events.
      [x] 96.1.2.2 Subtask - Include degraded remediation hints for disabled config, ineligible candidates, unresolved tool groups, and compactor failures.
      [x] 96.1.2.3 Subtask - Preserve event-sequence references for transcript debugging without replaying raw old context into prompts.

  [x] 96.2 Section - Configuration And Control Surfaces
    Add conservative controls for enabling, disabling, and tuning automatic compaction.

    [x] 96.2.1 Task - Add automatic compaction configuration
      Separate monitor recommendation thresholds from the decision to automatically compact.

      [x] 96.2.1.1 Subtask - Add `auto_compaction_enabled?` or equivalent policy flag with safe default behavior.
      [x] 96.2.1.2 Subtask - Add per-request and test overrides for auto-compaction behavior.
      [x] 96.2.1.3 Subtask - Validate invalid automatic compaction config as degraded metadata rather than disabling request-time budgeting.

    [x] 96.2.2 Task - Add explicit retry and disable paths
      Let operators and tests force a retry or disable automatic compaction without changing the monitor.

      [x] 96.2.2.1 Subtask - Add an explicit operator/workflow retry path for the latest eligible recommendation.
      [x] 96.2.2.2 Subtask - Add a skip/disable path that leaves monitor observations visible but stops automatic execution.
      [x] 96.2.2.3 Subtask - Keep explicit retries idempotent for already-compacted source spans.

  [x] 96.3 Section - Specs, ADRs, And Developer Guides
    Converge project guidance around the final automatic compaction lifecycle.

    [x] 96.3.1 Task - Update architecture records
      Bring specs and decisions up to date with automatic compaction and reset-aware projection behavior.

      [x] 96.3.1.1 Subtask - Update the context-management pod spec to replace historical "not yet dedicated" language with current pod and automatic behavior.
      [x] 96.3.1.2 Subtask - Update the compaction policy spec with automatic trigger, deferral, reset, and retry semantics.
      [x] 96.3.1.3 Subtask - Update the ADR if the automatic reset marker or configuration policy changes the accepted architecture.

    [x] 96.3.2 Task - Update contributor guidance and quality gates
      Make implementation and verification expectations clear for future context-management changes.

      [x] 96.3.2.1 Subtask - Update CodingPod and specialist-prompt guides with automatic compaction lifecycle details.
      [x] 96.3.2.2 Subtask - Update user-request-to-LLM docs with the new monitor, compact, reset, summary-injection, and request-time packing sequence.
      [x] 96.3.2.3 Subtask - Update quality-gate guidance with focused automatic compaction tests and when to run `mix memory.verify` or `mix source_graph.verify`.

  [x] 96.4 Section - Integration Tests
    End the track with cross-boundary verification for observability, configuration, documentation, and degraded behavior.

    [x] 96.4.1 Task - Add lifecycle observability coverage
      Verify product metadata distinguishes each automatic compaction state without leaking raw context.

      [x] 96.4.1.1 Subtask - Add coverage for pending, compacted, skipped, deferred, degraded, and explicit retry states.
      [x] 96.4.1.2 Subtask - Add sentinel tests proving raw prompt and tool-output content stay out of lifecycle metadata.
      [x] 96.4.1.3 Subtask - Add snapshot and event-stream assertions for reset sequence and summary ids.

    [x] 96.4.2 Task - Run final automatic compaction verification
      Verify the completed rollout across monitor, compactor, reset projection, runtime adoption, and docs.

      [x] 96.4.2.1 Subtask - Run focused Phase 93 through Phase 96 integration tests.
      [x] 96.4.2.2 Subtask - Run context-management and context-budget regression tests.
      [x] 96.4.2.3 Subtask - Run conversation runtime, coordinator, persistence, and snapshot tests.
      [x] 96.4.2.4 Subtask - Run `mix source_graph.verify` or `mix memory.verify` only if implementation touches graph prompt projection, provenance capture, or durable-memory boundaries.
