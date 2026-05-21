# ADR: CodingPod-Owned Context Management Pod And Automatic Compaction

## Status

Accepted and implemented.

## Context

Phases 85 through 88 introduced product-owned context budgeting. The current
runtime protects provider requests by packing prompt sections, specialist
history, and tool output at request time. That boundary is a hard safety net,
but it is intentionally reactive: it shapes the outgoing request and does not
rewrite the specialist's retained `AIContext`.

Long-lived work-item specialists can still accumulate history that is repeatedly
trimmed before each provider call. That keeps requests safe, but it loses the
benefit of older useful context unless another bounded summary is introduced.
We need a proactive lifecycle boundary that watches budget diagnostics,
summarizes older context, and exposes its behavior without turning raw
transcripts or tool output into prompt truth.

## Decision

Add a `ContextManagementPod` owned by each `CodingPod`.

The pod is work-item-scoped, not repository-global. Specialist history is
currently work-item and specialist-local, so proactive context lifecycle
management must stay in that same ownership boundary.

The pod contains:

- `BudgetMonitor`: an eager agent that observes context-budget diagnostics from
  specialist runs and decides when compaction should be requested.
- `ContextCompactor`: an AI-backed specialist or action boundary that converts
  older specialist history into bounded summaries.
- `CompactionStore`: a deterministic product-owned boundary for storing compact
  summaries, replacement metadata, and budget diagnostics.

Request-time budgeting remains mandatory. `JidoCode.ContextBudget` and
`JidoCode.ContextBudget.ReActRequestTransformer` continue to protect every
provider request even when proactive compaction is disabled, stale, or failed.

Automatic compaction is allowed, but it is not a hidden rewrite of conversation
history. Monitor recommendations become pending conversation state only when
their scope matches the active work item, workflow, specialist role,
conversation, and turn. The coordinator executes pending compaction at a
terminal boundary, stores an accepted summary, and appends
`conversation.context_compacted` as a reset marker. Snapshots use that marker to
remove covered old spans from prompt-facing shared context while preserving the
append-only event stream. Failures append
`conversation.context_compaction_failed` and execution continues through
request-time packing.

Automatic execution is controlled separately from monitoring through
`auto_compaction_enabled?`. Operators and tests can disable automatic execution
without deleting monitor observations, and can explicitly retry the latest
eligible recommendation. Retries remain idempotent for already-compacted source
spans.

Compaction output becomes bounded prompt context, such as
`specialist_summary`, `conversation_history`, or `compaction_summary` sections.
Raw old messages remain recoverable through governed conversation history and
workflow provenance, but they are not automatically re-expanded into prompts.

## Consequences

- Context lifecycle becomes explicit and observable instead of hidden inside
  provider request construction.
- Coding specialists can preserve useful older context through summaries while
  avoiding unbounded retained history.
- The system has two separate safeguards:
  - proactive compaction for quality and continuity
  - request-time packing for correctness and provider safety
- The compaction path must preserve tool-call protocol boundaries. It cannot
  summarize or remove half of an assistant/tool-result group.
- Compaction summaries are prompt aids, not durable repository memory. Any
  durable-memory adoption still goes through explicit governed memory
  boundaries.
- Failed or disabled compaction must degrade to existing request-time packing
  without blocking specialist execution.
- Context-management status and conversation snapshots now expose lifecycle
  metadata for recommended, pending, deferred, in-flight, compacted, skipped,
  blocked, and degraded states without storing raw old prompt or tool-output
  content.

## Related Specifications

- `../specs/context_management_pod.spec.md`
- `../specs/context_compaction_policy.spec.md`

## Related Planning

- `../.planning/phase-89-context-management-pod-foundation.md`
- `../.planning/phase-90-budget-monitor-runtime-adoption.md`
- `../.planning/phase-91-context-compactor-summary-lifecycle.md`
- `../.planning/phase-92-context-management-observability-and-contributor-convergence.md`
- `../.planning/phase-93-automatic-context-compaction-trigger-foundation.md`
- `../.planning/phase-94-conversation-context-reset-projection.md`
- `../.planning/phase-95-conversation-runtime-auto-compaction-adoption.md`
- `../.planning/phase-96-auto-compaction-observability-and-contributor-convergence.md`
