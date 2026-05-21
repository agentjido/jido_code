# Phase 94 - Conversation Context Reset Projection

<!-- covers: architecture.context_management_pod.context_lifecycle_is_observable -->
<!-- covers: architecture.context_compaction_policy.compaction_preserves_required_context -->
<!-- covers: architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory -->
<!-- covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-93-automatic-context-compaction-trigger-foundation.md`
- `specs/conversation_orchestration.spec.md`
- `specs/context_management_pod.spec.md`
- `specs/context_compaction_policy.spec.md`
- `lib/jido_code/conversations/event.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/snapshot.ex`
- `lib/jido_code/conversations/persistence.ex`
- `lib/jido_code/agent_workspace.ex`

## Relevant Assumptions / Defaults
- Conversation events remain the durable append-only history.
- Resetting conversation context means resetting prompt-facing projection state, not deleting historical events or provenance.
- Accepted compaction summaries are prompt context and remain trim/drop eligible under request-time budgeting.
- Debugging should recover original context through conversation history and provenance references, not automatic prompt expansion.

[ ] 94 Phase 94 - Conversation Context Reset Projection
  Add the append-only reset marker and snapshot projection rules that replace older raw conversation context with accepted compaction summaries.

  [ ] 94.1 Section - Canonical Context-Compacted Event
    Represent successful automatic compaction as a first-class conversation lifecycle event without storing raw old context.

    [ ] 94.1.1 Task - Add the reset event contract
      Define a canonical `conversation.context_compacted` event with enough metadata to explain the reset boundary.

      [ ] 94.1.1.1 Subtask - Add the event name to the canonical conversation event list.
      [ ] 94.1.1.2 Subtask - Include summary id, recommendation id, source span ids, policy id, workflow, specialist role, and reset sequence.
      [ ] 94.1.1.3 Subtask - Validate that event payloads do not include raw prompt text, raw tool output, or source file bodies.

    [ ] 94.1.2 Task - Persist reset events append-only
      Store reset events through the existing transition persistence path so replay remains deterministic.

      [ ] 94.1.2.1 Subtask - Append reset events after a summary is accepted by the compaction store.
      [ ] 94.1.2.2 Subtask - Persist the reset event and updated snapshot in the same transition as other coordinator events.
      [ ] 94.1.2.3 Subtask - Preserve all earlier `conversation.message_added`, turn, and tool events.

  [ ] 94.2 Section - Snapshot Projection After Reset
    Teach prompt-facing shared context to honor the latest reset boundary while preserving active work and required scope.

    [ ] 94.2.1 Task - Filter reset-covered raw context
      Derive `shared_context` from events, turns, and child work after the latest accepted reset marker.

      [ ] 94.2.1.1 Subtask - Exclude reset-covered referenced files, accepted tool results, and older latest-instruction candidates from prompt-facing context.
      [ ] 94.2.1.2 Subtask - Keep managed repo id, work item id, work resolution, scope, attachment mode, and pending clarification intact.
      [ ] 94.2.1.3 Subtask - Preserve active turn and awaiting-input context even when an older span was compacted.

    [ ] 94.2.2 Task - Surface active compaction summaries in shared context
      Make the reset projection explainable to runtime and operator surfaces without expanding old transcript content.

      [ ] 94.2.2.1 Subtask - Include active compaction summary ids and source span counts in `shared_context`.
      [ ] 94.2.2.2 Subtask - Include latest reset sequence and reset reason metadata.
      [ ] 94.2.2.3 Subtask - Keep summary text bounded to prompt assembly surfaces rather than general snapshot metadata unless explicitly needed.

  [ ] 94.3 Section - Replay And Resume Stability
    Ensure reset-aware snapshots restore consistently after coordinator restarts and reconnect recovery.

    [ ] 94.3.1 Task - Restore reset markers from persisted events
      Make cold-load state reconstruction produce the same reset-aware projection as an active coordinator.

      [ ] 94.3.1.1 Subtask - Rehydrate `conversation.context_compacted` events from `EventRecord`.
      [ ] 94.3.1.2 Subtask - Ensure `Snapshot.restore_state/3` preserves reset events and event sequence ordering.
      [ ] 94.3.1.3 Subtask - Confirm persisted snapshots keep reset metadata in bounded shared context.

    [ ] 94.3.2 Task - Preserve operator transcript continuity
      Keep conversation browsing complete while only prompt-facing context is reset.

      [ ] 94.3.2.1 Subtask - Ensure `conversation_events_since/3` still returns pre-reset events by sequence.
      [ ] 94.3.2.2 Subtask - Keep UI/event-stream recovery independent from prompt projection filtering.
      [ ] 94.3.2.3 Subtask - Document that reset boundaries affect future prompt context, not historical event access.

  [ ] 94.4 Section - Integration Tests
    Prove automatic reset markers are durable, replayable, and projection-only.

    [ ] 94.4.1 Task - Add reset projection coverage
      Exercise a conversation with old completed context, a compaction summary, and a reset event.

      [ ] 94.4.1.1 Subtask - Add coverage proving reset-covered accepted tool results leave `shared_context`.
      [ ] 94.4.1.2 Subtask - Add coverage proving required scope and pending clarification survive reset.
      [ ] 94.4.1.3 Subtask - Add coverage proving active summary ids and reset metadata are visible.

    [ ] 94.4.2 Task - Add persistence and replay coverage
      Verify that reset events survive persistence and do not erase historical transcript records.

      [ ] 94.4.2.1 Subtask - Add coverage for `Persistence.restore_state/1` with a reset event.
      [ ] 94.4.2.2 Subtask - Add coverage proving `events_since` still returns pre-reset history.
      [ ] 94.4.2.3 Subtask - Run conversation persistence, snapshot, and context-management focused tests.
