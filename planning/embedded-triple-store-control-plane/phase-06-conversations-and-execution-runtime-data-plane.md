# Phase 6 - Conversations And Execution Runtime Data Plane

Back to plan: [README](./README.md)

**Description:** This phase moves append-heavy runtime records onto the embedded semantic data plane. It covers conversations, conversation events, snapshots, context reset markers, execution workflows, sandbox sessions, runtime events, checkpoints, execution sessions, and sprite specs. Forge is treated as a legacy implementation name for this runtime layer, not a product domain to preserve.

- [x] 6 Phase - Conversations and execution runtime data plane.

  Description: Preserve runtime continuity and append-only evidence while replacing Ash-backed conversation persistence and legacy Forge/Ash runtime persistence.

## 6.1 Section - Conversation Persistence

**Description:** This section replaces conversation record, event, and snapshot storage.

- [x] 6.1 Section - Conversation persistence.

  Description: Conversation runtime should continue to use a product-owned persistence boundary, now backed by named graph writes.

  - [x] 6.1.1 Task - Implement conversation codecs and services.

    Description: Conversation identity, work-item attachment, event sequencing, and snapshot projection need semantic persistence.

    - [x] 6.1.1.1 Subtask - Implement codecs for conversation, conversation event, and conversation snapshot records.
    - [x] 6.1.1.2 Subtask - Rewire `JidoCode.Conversations.Persistence` to the product store.
    - [x] 6.1.1.3 Subtask - Preserve active conversation uniqueness per work item.

  - [x] 6.1.2 Task - Implement append-only event sequencing.

    Description: Conversation event writes need deterministic sequence behavior without database locks.

    - [x] 6.1.2.1 Subtask - Add sequence allocation through a store command or per-conversation counter subject.
    - [x] 6.1.2.2 Subtask - Preserve reconnect, replay, and snapshot recovery semantics.
    - [x] 6.1.2.3 Subtask - Preserve context reset and compaction marker projection behavior.

    Section verification: `mix test test/jido_code/conversations_test.exs test/jido_code/conversations/embedded_store_persistence_test.exs test/jido_code/conversations_context_compaction_test.exs` proves conversation lifecycle, active work-item uniqueness, event sequencing, snapshot recovery, and compaction-marker replay through isolated embedded product stores.

## 6.2 Section - Execution Runtime Disposition And Persistence

**Description:** This section classifies legacy Forge pieces, preserves useful execution-runtime abstractions, and replaces Forge Ash/Postgres persistence with semantic records.

- [x] 6.2 Section - Execution runtime disposition and persistence.

  Description: Sandbox sessions and execution sessions should keep resumability and auditability without preserving Forge as a first-class product domain.

  - [x] 6.2.1 Task - Classify and rename legacy Forge concepts.

    Description: The current `JidoCode.Forge` namespace should be split into runtime pieces to keep, stale surfaces to delete, and Ash/Postgres data-plane pieces to replace.

    - [x] 6.2.1.1 Subtask - Inventory `JidoCode.Forge` modules into keep, rename, and delete categories.
    - [x] 6.2.1.2 Subtask - Mark `JidoCode.Forge.Resources.*`, `JidoCode.Forge.Persistence`, `JidoCode.Forge.Domain`, Forge migrations, and Forge snapshots as Ash/Postgres removal targets.
    - [x] 6.2.1.3 Subtask - Rename product-facing references from Forge to execution runtime or sandbox sessions, and remove stale Forge LiveView planning assumptions.

    Disposition notes: keep `Manager`, `SpriteSession`, runners, `SpriteClient`, PubSub, redaction, `StepHandler`, and streaming workers as runtime implementation modules until the namespace removal pass. Replace/delete targets are `JidoCode.Forge.Resources.*`, `JidoCode.Forge.Domain`, Forge Ash migrations, Forge resource snapshots, and Ash-shaped test fixtures. `JidoCode.Forge.Persistence` is now a compatibility facade over `JidoCode.ExecutionRuntime.RecordStore` and remains only until callers move to execution-runtime naming.

  - [x] 6.2.2 Task - Implement execution runtime codecs and services.

    Description: Runtime records need lifecycle updates, event logging, checkpoint links, execution session output metadata, and redaction without Ash resources.

    - [x] 6.2.2.1 Subtask - Implement codecs for execution workflow, sandbox session, runtime event, checkpoint, exec session, and sprite spec records.
    - [x] 6.2.2.2 Subtask - Rewire runtime persistence, runtime operations, and streaming exec session worker writes to the product store.
    - [x] 6.2.2.3 Subtask - Preserve channel and prompt redaction, store bounded output summaries in graph records, and keep full output only in an explicit artifact store.

    Section verification: `mix test test/jido_code/execution_runtime/record_store_test.exs test/jido_code/forge/persistence_redaction_test.exs test/jido_code/forge/event_logger_test.exs test/jido_code/forge/pubsub_redaction_test.exs` proves sandbox lifecycle, event logging, exec summaries, checkpoint links, and redaction through isolated embedded product stores. `mix test test/jido_code/control_plane/codecs_test.exs test/jido_code/control_plane/semantic_identity_test.exs test/jido_code/control_plane/ontology_topology_integration_test.exs` proves the new execution-runtime codecs and ontology topology.

## 6.3 Section - Runtime Query Projections

**Description:** This section provides read models for conversation and execution runtime operator surfaces.

- [x] 6.3 Section - Runtime query projections.

  Description: Operator surfaces need efficient projections without relying on Ash preload or SQL sorting.

  - [x] 6.3.1 Task - Add conversation projections.

    Description: Conversation routes and dashboards need active, historical, clarification, and degraded-state projections.

    - [x] 6.3.1.1 Subtask - Query active conversations by managed repo and work item.
    - [x] 6.3.1.2 Subtask - Query event windows by conversation sequence.
    - [x] 6.3.1.3 Subtask - Query latest snapshot and reset-aware prompt projection metadata.

  - [x] 6.3.2 Task - Add execution runtime projections.

    Description: Runtime surfaces need sandbox session status, latest checkpoint, execution history, and event streams.

    - [x] 6.3.2.1 Subtask - Query sandbox sessions by managed repo, status, workflow, and updated time.
    - [x] 6.3.2.2 Subtask - Query latest checkpoint and execution session summary.
    - [x] 6.3.2.3 Subtask - Query event history with bounded limits.

    Section verification: `mix test test/jido_code/conversations/projections_test.exs test/jido_code/execution_runtime/projections_test.exs test/jido_code/conversations/embedded_store_persistence_test.exs test/jido_code/execution_runtime/record_store_test.exs` proves active, historical, clarification, event-window, reset-aware snapshot, sandbox-session, latest-checkpoint, execution-history, and bounded runtime-event projections against isolated embedded product stores.

## 6.4 Section - Integration Tests

**Description:** This final section proves runtime persistence works under realistic conversation and execution runtime scenarios.

- [x] 6.4 Section - Integration tests.

  Description: Exercise append-heavy writes, replay, recovery, and redaction against the embedded store.

  - [x] 6.4.1 Task - Add conversation runtime integration coverage.

    Description: Conversation tests should prove event replay and snapshots are durable without Ash.

    - [x] 6.4.1.1 Subtask - Start a work-item conversation, append turns, and replay events by sequence.
    - [x] 6.4.1.2 Subtask - Persist a snapshot and recover runtime state from the embedded store.
    - [x] 6.4.1.3 Subtask - Prove compaction reset markers affect prompt projection without deleting historical events.

  - [x] 6.4.2 Task - Add execution runtime integration coverage.

    Description: Runtime tests should prove lifecycle updates and output redaction survive store replacement.

    - [x] 6.4.2.1 Subtask - Create an execution workflow, sandbox session, event stream, execution session, and checkpoint.
    - [x] 6.4.2.2 Subtask - Resume a session from latest checkpoint metadata.
    - [x] 6.4.2.3 Subtask - Assert redacted output and prompt fields stay bounded in graph literals.

    Section verification: `mix test test/jido_code/control_plane/embedded_store_phase_six_integration_test.exs` proves conversation replay, snapshot recovery, reset-aware prompt projection, execution workflow/session/event/checkpoint persistence, latest-checkpoint resume metadata, and redacted bounded output through an isolated embedded product store.
