# Phase 42 - Conversation Persistence And Product Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped -->
<!-- covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced -->
<!-- covers: architecture.conversation_orchestration.steering_preserves_short_term_context -->
<!-- covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/work_synthesis.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.factory_control_plane.md`
- `../decisions/jido_code.jido_agent_os_integration.md`
- `README.md`
- `AGENTS.md`
- `CONTRIBUTING.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/operations/work_item.ex`
- `lib/jido_code_web/live/demos/chat_live.ex`
- `lib/jido_code_web/live/forge/show_live.ex`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 39 through 41 established the conversation coordinator, interruptible execution model, and event-driven UI delivery path.
- Productive coding conversations need durable history plus a bounded short-term collaboration context so steering can redirect work without forcing the human to restate everything.
- Persisted conversation state must remain secondary to governed product truth: conversations inform and steer work, but they do not replace `ManagedRepo` and `WorkItem` as the durable factory objects.
- Contributor guidance and rollout defaults should converge on the new event-driven, interruptible conversation model once the persistence and steering layer is in place.

[x] 42 Phase 42 - Conversation Persistence And Product Convergence
  Persist append-only conversation history and current snapshots, preserve bounded shared context across steering, and converge the new conversation model with the factory control plane and contributor defaults.

  [x] 42.1 Section - Durable Conversation History And Shared Context
    Add the persistence and context-rehydration behavior needed to replay conversations, recover state, and preserve bounded collaboration context across interruption and steering.

    [x] 42.1.1 Task - Persist append-only event history and materialized snapshots
      Make the event-driven conversation model durable so replay, reconnect, and degraded continuity do not depend on transient runtime memory alone.

      [x] 42.1.1.1 Subtask - Introduce durable storage for append-only conversation events with stable sequence and correlation metadata.
      [x] 42.1.1.2 Subtask - Persist current conversation snapshots for efficient initial load and degraded fallback without replaying the entire event history every time.
      [x] 42.1.1.3 Subtask - Keep persistence boundaries explicit about what is durable history, what is derived snapshot state, and what remains transient runtime state.

    [x] 42.1.2 Task - Preserve bounded short-term collaboration context across steering
      Make steering productive by carrying forward the right shared context while preventing superseded partial output from masquerading as final truth.

      [x] 42.1.2.1 Subtask - Persist or rehydrate bounded short-term context such as active work item, referenced files, accepted tool results, and pending clarification state.
      [x] 42.1.2.2 Subtask - Define what superseded partial output stays as traceable history versus what must not be treated as current answer state.
      [x] 42.1.2.3 Subtask - Keep short-term context bounded and explainable so steering improves productivity without turning the conversation into an unbounded hidden memory store.

  [x] 42.2 Section - Factory Work, Surface, And Contributor Convergence
    Align the new conversation model with durable work synthesis, product surfaces, and contributor guidance so interruption and event-driven conversation become the repo default.

    [x] 42.2.1 Task - Converge conversations with work synthesis and factory work steering
      Ensure conversations become a first-class way to steer governed work without creating a parallel durable truth system.

      [x] 42.2.1.1 Subtask - Align conversation steering with work-item reprioritization, redirection, and existing-work attachment behavior.
      [x] 42.2.1.2 Subtask - Preserve actor attribution and auditability when conversation commands steer durable work decisions.
      [x] 42.2.1.3 Subtask - Keep `ManagedRepo` and `WorkItem` as the canonical product records even while conversation history remains durable and queryable.

    [x] 42.2.2 Task - Align docs, defaults, and rollout guidance to the new conversation model
      Update contributor and architecture guidance so new work builds on the event-driven, interruptible conversation model by default.

      [x] 42.2.2.1 Subtask - Update planning, contributor, and architecture guidance to explain the control lane, append-only event model, and bounded shared context contract.
      [x] 42.2.2.2 Subtask - Deprecate polling-oriented assumptions in the conversation guidance and point new surfaces at the event-driven path.
      [x] 42.2.2.3 Subtask - Keep operator-facing language product-oriented, avoiding raw runtime, provider, or queueing jargon in surfaced defaults.

  [x] 42.3 Section - Phase 42 Integration Tests
    Verify persistence, replay, steering context, and product convergence all work together before the new conversation model is treated as the durable default.

    [x] 42.3.1 Task - Persistence and replay scenarios
      Prove durable conversation history and snapshots support recovery, replay, and degraded continuity cleanly.

      [x] 42.3.1.1 Subtask - Add coverage proving append-only event history can rebuild or validate current conversation snapshots.
      [x] 42.3.1.2 Subtask - Add coverage proving persisted snapshots support initial load and degraded fallback without losing sequence integrity.
      [x] 42.3.1.3 Subtask - Add coverage proving replay and recovery preserve stable conversation, turn, and tool-call identifiers.

    [x] 42.3.2 Task - Steering and convergence scenarios
      Prove the final conversation model preserves productivity while staying aligned to governed work and product-owned surfaces.

      [x] 42.3.2.1 Subtask - Add coverage proving steering preserves bounded short-term context without presenting superseded partial output as current truth.
      [x] 42.3.2.2 Subtask - Add coverage proving conversation-driven work steering remains auditable and aligned to canonical `ManagedRepo` and `WorkItem` records.
      [x] 42.3.2.3 Subtask - Verify the spec workspace, planning index, and contributor docs remain coherent after Phase 42 converges the new conversation model.
