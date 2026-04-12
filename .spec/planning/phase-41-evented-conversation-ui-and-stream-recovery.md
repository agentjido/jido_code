# Phase 41 - Evented Conversation UI And Stream Recovery

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced -->
<!-- covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable -->
<!-- covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state -->
<!-- covers: architecture.conversation_orchestration.expensive_work_announces_intent -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `lib/jido_code_web/live/demos/chat_live.ex`
- `lib/jido_code_web/live/forge/show_live.ex`
- `lib/jido_code/forge/pubsub.ex`
- `lib/jido_code/orchestration/run_pubsub.ex`
- `lib/jido_code_web/components/`
- `test/jido_code_web/live/`
- `test/jido_code/forge/`

## Relevant Assumptions / Defaults
- Phases 39 and 40 established canonical conversation scope, coordinator ownership, the control lane, and cancellable child execution.
- The Forge surfaces already demonstrate event-driven delivery, reconnect handling, and degraded fallback patterns that should inform the canonical conversation UI.
- Polling snapshots may remain as a temporary recovery mechanism, but they should stop being the steady-state update path for productive coding conversations.
- Event delivery must remain product-owned, redactable, and sequence-aware before richer browser surfaces depend on it.

[ ] 41 Phase 41 - Evented Conversation UI And Stream Recovery
  Replace polling-oriented conversation updates with sequenced event delivery, product-owned PubSub topics, and reconnect or degraded recovery semantics that keep coding conversations legible while work continues.

  [ ] 41.1 Section - Append-Only Conversation Event Model
    Define the event taxonomy, sequence semantics, and snapshot relationship that power both UI streaming and reconnect recovery.

    [ ] 41.1.1 Task - Introduce the canonical conversation event taxonomy
      Make turn, tool, and intent lifecycle visible through typed product events rather than through opaque runtime snapshots.

      [ ] 41.1.1.1 Subtask - Define canonical event names for message creation, turn admission, intent announcements, deltas, tool lifecycle, cancellation, and terminal settlement.
      [ ] 41.1.1.2 Subtask - Add monotonic per-conversation sequence numbers, stable identifiers, timestamps, and correlation metadata needed for replay and reconnect.
      [ ] 41.1.1.3 Subtask - Keep event payloads product-readable and redactable so UI subscribers do not parse provider-native transport details.

    [ ] 41.1.2 Task - Add product-owned conversation PubSub and snapshot shaping
      Deliver live events and materialized snapshots through reusable infrastructure instead of feature-local LiveView polling loops.

      [ ] 41.1.2.1 Subtask - Introduce conversation PubSub topics and helpers modeled on existing run and Forge event helpers.
      [ ] 41.1.2.2 Subtask - Add materialized conversation snapshot shaping for initial load, reconnect, and degraded-mode fallback.
      [ ] 41.1.2.3 Subtask - Keep event publication and snapshot shaping aligned to product-owned redaction and diagnostics behavior.

  [ ] 41.2 Section - LiveView Adoption And Recovery Behavior
    Move the conversation UI onto live events and make reconnect or continuity gaps explicit instead of silently depending on fast polling.

    [ ] 41.2.1 Task - Replace steady-state snapshot polling with event subscriptions
      Turn the canonical conversation surfaces into event subscribers that stream incremental updates and only fetch snapshots when needed.

      [ ] 41.2.1.1 Subtask - Update the demo or early conversation surface to subscribe to conversation PubSub topics and stream turn or tool updates.
      [ ] 41.2.1.2 Subtask - Render intent announcements, streaming deltas, tool lifecycle, and cancellation progress through LiveView streams or equivalent bounded helpers.
      [ ] 41.2.1.3 Subtask - Remove the assumption that rapid polling is the normal update loop for productive coding conversations.

    [ ] 41.2.2 Task - Add reconnect, continuity, and degraded-mode handling
      Keep the UI understandable when live delivery drops or only persisted conversation state is currently available.

      [ ] 41.2.2.1 Subtask - Track the last accepted event sequence in the browser-facing surface and request continuity from the next sequence on reconnect.
      [ ] 41.2.2.2 Subtask - Add explicit continuity-gap messaging when events are missed or only snapshot-based recovery is possible.
      [ ] 41.2.2.3 Subtask - Keep degraded messaging product-oriented rather than exposing raw PubSub, provider, or runtime internals.

  [ ] 41.3 Section - Phase 41 Integration Tests
    Verify the event stream, UI adoption, and reconnect behavior all work together before persistence and broader product convergence build on them.

    [ ] 41.3.1 Task - Event and PubSub scenarios
      Prove conversation events are sequenced, broadcast correctly, and coherent with snapshots.

      [ ] 41.3.1.1 Subtask - Add coverage proving conversation events carry monotonic per-conversation sequence numbers and stable identifiers.
      [ ] 41.3.1.2 Subtask - Add coverage proving PubSub subscribers receive typed turn, tool, cancellation, and intent events through product-owned topics.
      [ ] 41.3.1.3 Subtask - Add coverage proving snapshots and event streams remain coherent during normal turn execution.

    [ ] 41.3.2 Task - UI and recovery scenarios
      Prove the browser-facing conversation surface behaves well across live delivery, reconnect, and degraded operation.

      [ ] 41.3.2.1 Subtask - Add coverage proving the conversation surface renders live updates from PubSub without relying on steady-state polling.
      [ ] 41.3.2.2 Subtask - Add coverage proving reconnect resumes from the next event sequence when continuity is available.
      [ ] 41.3.2.3 Subtask - Verify degraded-mode messaging remains clear and product-owned when only snapshot recovery is available.
