# Context Compaction Policy Specification

## Purpose

Define when context compaction is allowed, what it may summarize, how summaries
are represented, and what evidence must be recorded.

## Subject Tags

- `architecture.context_compaction_policy.compaction_is_threshold_driven`
- `architecture.context_compaction_policy.compaction_preserves_required_context`
- `architecture.context_compaction_policy.tool_protocol_boundaries_are_preserved`
- `architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory`
- `architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata`
- `architecture.context_compaction_policy.compaction_degrades_to_request_time_packing`

## Trigger Policy

Compaction may be recommended when any of these conditions are true:

- retained specialist history repeatedly trims under the configured history
  budget
- estimated retained history exceeds a configured high-water mark
- tool-output truncation repeatedly affects the same specialist thread
- optional context sections are dropped often enough to reduce continuity
- an operator or workflow explicitly requests proactive context reduction

Compaction should not run on every turn. The monitor should debounce and avoid
duplicate compactions for the same unchanged span.

## Eligible Context

Eligible context includes older specialist-local messages and previously packed
tool outputs that are no longer part of the active request or current
assistant/tool-result group.

Ineligible context includes:

- the current user request
- governed repository and work-item scope
- pending clarification context
- the current unresolved tool-call group
- system prompts
- raw source files or tool outputs that are better re-read through tools

## Summary Shape

A compaction summary must include:

- summary id
- specialist id or role
- work item id
- workflow
- source message span identifiers
- estimated original and summary sizes
- summary text
- created-at timestamp
- retention class
- diagnostics and remediation when degraded

The summary text must be bounded and suitable for use as a prompt section.

## Prompt Use

Prompt assembly may include compaction summaries as typed sections. The section
name should make the distinction clear, such as `specialist_summary`,
`conversation_history`, or `compaction_summary`.

The request-time context-budget packer may trim or drop compaction summaries
like any other optional or important section. Compaction summaries never become
required context.

## Product And Memory Boundaries

Compaction summaries are prompt context and runtime continuity aids. They are
not durable repository memory.

If a summary contains a durable decision, invariant, convention, or lesson,
that material can only become durable memory through the explicit governed
memory adoption boundary.

Compaction metadata must not persist raw prompt bodies or raw tool output.

## Safety Rules

Compaction must preserve assistant/tool-result protocol integrity. A compacted
span may only replace complete protocol-safe groups.

Compaction must be idempotent for the same source span and summary policy.

Compaction must be reversible for debugging through governed conversation
history or provenance references, not through automatic prompt expansion.

## Verification Requirements

Tests must prove:

- high-water mark and repeated-trim triggers are deterministic
- ineligible required context is never compacted away
- assistant/tool-result groups remain valid after compaction
- compaction summaries are bounded prompt sections
- compaction summaries are not written as durable memory
- compaction failure falls back to request-time packing
