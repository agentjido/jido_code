---
id: jido_code.conversation_history_long_term_capture
status: accepted
date: 2026-04-30
affects:
  - package.jido_code
  - architecture.conversation_orchestration
  - architecture.memory_capture_plane
  - architecture.memory_graph_product_adoption
  - architecture.factory_control_plane
  - architecture.memory_graph_surface_rollout_and_governance_actions
  - architecture.memory_graph_workflow_and_operator_expansion
  - architecture.operator_surface_information_architecture
  - architecture.run_governance
related:
  - jido_code.interruptible_conversation_orchestration
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.memory_graph_product_adoption
  - jido_code.work_item_scoped_conversations_as_canonical_productive_threads
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->
<!-- covers: architecture.memory_capture_plane.conversation_history_is_captured_as_workflow_provenance -->
<!-- covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections -->

# Conversation History Long-Term Capture

## Context

`Jido.Code` already has a clear short-term conversation continuity model:
productive conversations persist append-only events, materialized snapshots,
work-item linkage, clarification state, and route-owned transcript continuity.

That is enough to resume work on the same repository route, but it is not the
same as long-term semantic recall.

When operators later ask why a work item, decision, or repository convention
exists, the current system can often answer only by reopening conversation
state or by following governed records that preserved some origin linkage.
That leaves a gap between:

- short-term transcript continuity for one active conversation
- durable repository-scoped provenance and memory that can be queried across
  sessions, revisions, and governed records

At the same time, the memory stack already has an explicit safety boundary:
transient prompt text, tool output, and conversation state do not become
durable memory just because they existed. Flattening full transcripts into the
`memory` graph would violate that rule, create a second uncontrolled truth
lane, and make later retrieval noisy and hard to govern.

The product therefore needs a durable rule for what happens if conversation
history crosses from the conversation subsystem into the repository semantic
stack.

## Decision

When `Jido.Code` captures productive conversation history for long-term recall,
it shall do so as provenance first, not as automatic durable memory.

The canonical split is:

- conversation snapshots and event history remain the primary continuity system
  for reopening and supervising the active conversation itself
- bounded long-term capture of conversation turns, steering, clarification,
  repo/work-item attachment, and follow-up lineage enters
  `workflow_provenance`
- durable repository memory in the `memory` graph is created only from
  explicitly adopted or classified takeaways such as decisions, conventions,
  lessons, known issues, patterns, or open questions

This means the product may preserve long-term semantic context from productive
conversation, but it must reduce and classify that context before it behaves
like durable memory.

The product shall therefore prefer:

- provenance records that explain which conversation, turn, actor, revision,
  and work item produced later governed work
- bounded projections that let workflows and operator surfaces inspect
  conversation-derived origin context without reading raw graph internals
- route-owned recall cards on repo-detail memory and governed-run follow-up
  surfaces that reopen the canonical repository conversation when an operator
  needs full transcript continuity
- explicit adoption paths when a conversation outcome should become a durable
  `Fact`, `Decision`, `Convention`, `KnownIssue`, `LessonLearned`,
  `OpenQuestion`, `Pattern`, or similar memory class

The product shall reject:

- treating full transcript text as the default durable memory representation
- assuming every prompt or assistant response is worth long-term recall
- exposing the memory graph as a generic transcript browser
- letting semantic capture replace governed product records as the source of
  truth for work, evidence, or decisions

## Consequences

- The product gains a path for long-term explainability of conversation-driven
  work without confusing transcript continuity with durable repository memory.
- Workflow provenance can answer origin questions such as why a work item,
  patch, or decision exists without reopening the full route transcript.
- Later planning, execution, review, and explanation workflows can request
  conversation-derived context explicitly through bounded product-owned memory
  and provenance services.
- The memory graph stays useful because only intentionally adopted takeaways
  become durable memory classes; raw transcripts do not flood the `memory`
  graph.
- Conversation snapshots remain the canonical continuity and recovery system for
  active conversation UI, rather than being replaced by semantic replay.
