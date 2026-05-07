# Phase 74 - Conversation Provenance Long-Term Capture Foundation

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first -->
<!-- covers: architecture.memory_capture_plane.conversation_history_is_captured_as_workflow_provenance -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/work_synthesis.spec.md`
- `../decisions/jido_code.conversation_history_long_term_capture.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.work_item_scoped_conversations_as_canonical_productive_threads.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/event.ex`
- `lib/jido_code/conversations/persistence.ex`
- `lib/jido_code/conversations/snapshot.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/memory_graph/capture_envelope.ex`
- `lib/jido_code/memory_graph/capture_writer.ex`
- `test/jido_code/phase_forty_one_integration_test.exs`
- `test/jido_code/phase_forty_two_integration_test.exs`
- `test/jido_code/phase_forty_seven_integration_test.exs`

## Relevant Assumptions / Defaults
- Phases 29 through 37 already established the bounded workflow-provenance
  capture plane, typed governed references, and product-safe memory graph
  boundaries.
- Phases 39 through 52 already established durable conversation snapshots,
  append-only eventing, clarification recovery, deterministic workflow routing,
  and governed work-item attachment.
- The new ADR rejects flattening full transcript history into durable `memory`
  and instead requires provenance-first long-term recall.
- Conversation snapshots and event history remain the continuity and recovery
  system for active conversation UI even after semantic provenance capture
  begins.

[x] 74 Phase 74 - Conversation Provenance Long-Term Capture Foundation
  Add the provenance-first long-term capture path for productive conversations
  so later workflows and governed records can explain conversation-driven work
  without turning the memory graph into a transcript dump.

  [x] 74.1 Section - Long-Term Conversation Capture Model And Boundaries
    Define exactly what conversation-origin context may cross from the
    conversation subsystem into the semantic stack and what must remain route
    continuity only.

    [x] 74.1.1 Task - Formalize bounded long-term conversation lineage
      Specify the durable conversation-origin elements that deserve long-term
      provenance capture instead of relying on active transcript replay.

      [x] 74.1.1.1 Subtask - Define the bounded lineage set such as
        conversation identity, turn identity, actor attribution, steering
        events, clarification state, work-item attachment, and governed follow-up
        origin links.
      [x] 74.1.1.2 Subtask - Preserve managed-repository scope, revision
        context, and governed references on long-term capture so later recall
        stays repository-scoped and explainable.
      [x] 74.1.1.3 Subtask - Reject full transcript dumping, raw delta replay,
        or automatic durable-memory insertion as the long-term capture model.

    [x] 74.1.2 Task - Extend the canonical capture-plane contract
      Fit conversation-origin capture into the existing memory-capture seams
      instead of inventing a second semantic write path.

      [x] 74.1.2.1 Subtask - Add typed capture-envelope shapes for
        conversation-origin provenance that remain separate from raw transcript
        storage concerns.
      [x] 74.1.2.2 Subtask - Route conversation-origin capture into
        `workflow_provenance` rather than `memory`.
      [x] 74.1.2.3 Subtask - Preserve stable code, work-item, run, evidence,
        and decision references through the existing typed governed-reference
        contract.

  [x] 74.2 Section - Conversation Runtime And Persistence Seam Adoption
    Connect the new long-term capture model to the real conversation boundaries
    where origin context already becomes durable and product-owned.

    [x] 74.2.1 Task - Emit provenance from productive conversation boundaries
      Make the conversation runtime record durable lineage at the points where
      work, clarification, or steering semantics become product-significant.

      [x] 74.2.1.1 Subtask - Capture bounded provenance when productive turns
        start, steer, request clarification, attach to governed work, and
        settle.
      [x] 74.2.1.2 Subtask - Preserve origin linkage when repo-scoped intake
        promotes into canonical `WorkItem` scope.
      [x] 74.2.1.3 Subtask - Keep provenance emission bounded under resume,
        reconnect, and degraded continuity paths instead of duplicating every
        event as a semantic write.

    [x] 74.2.2 Task - Preserve the continuity-system split
      Keep conversation persistence and long-term semantic provenance from
      collapsing into one overloaded storage model.

      [x] 74.2.2.1 Subtask - Keep snapshots and append-only conversation events
        as the canonical route continuity and recovery surface.
      [x] 74.2.2.2 Subtask - Ensure missing, stale, or recovering provenance
        does not break route transcript continuity or active conversation
        supervision.
      [x] 74.2.2.3 Subtask - Avoid a second semantic transcript browser by
        keeping transcript reopening on conversation routes and long-term origin
        lookup in bounded provenance projections.

  [x] 74.3 Section - Phase 74 Integration Tests
    Prove the new provenance-first capture path records the right long-term
    context and preserves the existing conversation continuity model.

    [x] 74.3.1 Task - Add conversation-provenance capture coverage
      Verify productive conversation lineage becomes bounded
      `workflow_provenance` without being mistaken for durable memory.

      [x] 74.3.1.1 Subtask - Add coverage proving productive conversation
        lineage records into `workflow_provenance` with managed-repository,
        actor, revision, and governed-work linkage intact.
      [x] 74.3.1.2 Subtask - Add coverage proving steering, clarification, and
        governed-work attachment remain queryable as provenance without dumping
        full transcript text into `memory`.
      [x] 74.3.1.3 Subtask - Add coverage proving conversation snapshots and
        route continuity still recover correctly when provenance capture is
        absent, delayed, or recovering.
