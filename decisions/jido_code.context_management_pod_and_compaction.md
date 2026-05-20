# ADR: CodingPod-Owned Context Management Pod And Proactive Compaction

## Status

Accepted for planning.

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

## Related Specifications

- `../specs/context_management_pod.spec.md`
- `../specs/context_compaction_policy.spec.md`

## Related Planning

- `../.planning/phase-89-context-management-pod-foundation.md`
- `../.planning/phase-90-budget-monitor-runtime-adoption.md`
- `../.planning/phase-91-context-compactor-summary-lifecycle.md`
- `../.planning/phase-92-context-management-observability-and-contributor-convergence.md`
