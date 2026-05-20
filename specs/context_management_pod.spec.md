# Context Management Pod Specification

## Purpose

Define the work-item-scoped pod that proactively manages specialist context
growth without replacing the request-time context-budget safety net.

## Subject Tags

- `architecture.context_management_pod.coding_pod_owns_context_management`
- `architecture.context_management_pod.budget_monitor_observes_budget_diagnostics`
- `architecture.context_management_pod.context_compactor_is_bounded_specialist`
- `architecture.context_management_pod.compaction_store_is_product_owned`
- `architecture.context_management_pod.request_time_budgeting_remains_hard_guard`
- `architecture.context_management_pod.context_lifecycle_is_observable`

## Current Truth

The product already has `JidoCode.ContextBudget` and a ReAct request
transformer that pack context at provider-request time. That layer is mandatory
and remains the final safety check for every specialist request.

There is not yet a dedicated agent or pod that watches accumulated context and
proactively compresses retained specialist history.

## Required Architecture

`CodingPod` owns a `ContextManagementPod` for each governed work item.

The context-management pod contains:

- `BudgetMonitor`
- `ContextCompactor`
- `CompactionStore`

The pod is work-item-scoped because specialist `AIContext` is work-item and
specialist-local. Repository-scoped context management is not allowed to mix
history across work items.

## BudgetMonitor Contract

`BudgetMonitor` is an eager `Jido.Agent`.

It observes:

- context-budget summaries from specialist prompt packing
- ReAct history packing diagnostics
- tool-output budget diagnostics
- workflow, specialist, work item, and conversation identifiers

It emits:

- no-op decisions when current context is healthy
- compaction recommendations when threshold policy is crossed
- blocked or degraded diagnostics when compaction is unsafe or unavailable

The monitor does not mutate specialist history directly. It requests compaction
through product-owned actions or signals.

## ContextCompactor Contract

`ContextCompactor` is a bounded AI-backed specialist or equivalent action
boundary. It accepts a protocol-safe compaction candidate and returns a summary
plus replacement metadata.

It must:

- preserve the active request and current unresolved tool-call group
- summarize only eligible older context spans
- include source span identifiers and token estimates
- produce summaries with explicit retention class and workflow scope
- keep raw prompt bodies and raw tool output out of diagnostics

It must not:

- replace request-time `ContextBudget` packing
- classify compaction summaries as durable memory
- mix context across specialists or work items
- drop one side of an assistant/tool-result group

## CompactionStore Contract

`CompactionStore` is deterministic product code, not an LLM-owned memory.

It stores:

- compaction summary text
- source span identifiers
- replacement markers
- budget diagnostics before and after compaction
- workflow, specialist, work item, conversation, and revision identifiers

It exposes bounded summaries back to prompt assembly. It does not expose raw old
messages as prompt context unless a later explicit debug-only boundary accepts
that behavior.

## Runtime Integration

`AgentWorkspace` and specialist runners pass context-budget diagnostics to the
context-management pod after specialist calls. The pod may request compaction
before the next specialist call.

Prompt assembly may include a bounded compaction summary section when available.
The request-time `ContextBudget` layer still packs the final prompt and
retained history.

## Degraded Behavior

If monitoring or compaction is unavailable, specialist execution continues with
request-time budgeting only.

If compaction fails, the failure is captured as diagnostics and should not
block the current turn unless the existing request-time budget layer cannot fit
required sections.

## Verification Requirements

Tests must prove:

- the pod is created and addressed per work item
- monitor decisions are based on budget diagnostics, not raw prompt inspection
- compaction requests preserve protocol-safe message groups
- summaries can be injected as bounded prompt sections
- request-time packing still runs after compaction
- disabled or failed compaction degrades safely
