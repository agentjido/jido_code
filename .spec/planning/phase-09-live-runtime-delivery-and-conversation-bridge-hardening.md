# Phase 9 - Live Runtime Delivery and Conversation Bridge Hardening

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_driver.spec.md`
- `../specs/coding_assistance_boundary.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../specs/execution_pipeline.spec.md`
- `../decisions/jido_code.jido_os_public_turn_live_delivery_adoption.md`
- `JidoCode.CodingAssistance`
- `JidoCode.Conversations.Driver`
- `JidoCode.Conversations.TurnBridge`
- `JidoCode.Conversations.EventBridge`
- `JidoCode.CodeServer`

## Relevant Assumptions / Defaults
- Phase 8 has established product-owned runtime gateway conventions and typed capability posture.
- Public live turn delivery is now available in `jido_os`, and replay remains the canonical recovery path.
- Subscriber-facing UI contracts must remain stable even if transport and bridge behavior change underneath them.

[ ] 9 Phase 9 - Live Runtime Delivery and Conversation Bridge Hardening
  Replace polling-first coding progress delivery with product-owned adoption of public live turn subscription, replay fallback, and explicit terminal handoff so the conversation bridge reflects the newer runtime-service model without destabilizing current subscribers.

  [x] 9.1 Section - Live Subscription Boundary Adoption
    Extend the coding boundary so live turn delivery becomes a first-class product seam instead of an implementation detail hidden in the bridge.

    [x] 9.1.1 Task - Add live subscribe and unsubscribe wrappers to `JidoCode.CodingAssistance`
      Expose public live turn delivery through the product-owned boundary before changing the conversation bridge transport.

      [x] 9.1.1.1 Subtask - Add wrappers for public `subscribe_turn_events` and `unsubscribe_turn_events`.
      [x] 9.1.1.2 Subtask - Preserve actor, session, project, request, correlation, workspace, and optional resume-cursor context across every live-delivery request.
      [x] 9.1.1.3 Subtask - Return product-owned acknowledgement shapes needed by the bridge instead of leaking runtime-native delivery envelopes directly.

    [x] 9.1.2 Task - Normalize live acknowledgement and resume semantics at the product boundary
      Make the bridge consume stable product-owned inputs for cursor, replay join, terminal snapshot, and detachment behavior.

      [x] 9.1.2.1 Subtask - Normalize resumable cursor, replay-join, and terminal-handoff metadata into product-local bridge inputs.
      [x] 9.1.2.2 Subtask - Preserve typed unavailable, withheld, denied, invalid-cursor, and detached outcomes at the boundary.
      [x] 9.1.2.3 Subtask - Keep replay, turn read, artifact read, and operator review available as fallback or verification surfaces.

  [ ] 9.2 Section - Conversation Bridge Transport Modernization
    Move the conversation bridge from polling-first replay loops to live-delivery-first behavior while keeping replay as the canonical recovery path.

    [ ] 9.2.1 Task - Prefer live delivery for steady-state subscriber updates
      Let current subscribers benefit from the richer runtime-delivery path without receiving a second protocol.

      [ ] 9.2.1.1 Subtask - Update `TurnBridge` to admit and consume live turn delivery before falling back to replay polling.
      [ ] 9.2.1.2 Subtask - Preserve translation into the existing conversation event contract through `EventBridge`.
      [ ] 9.2.1.3 Subtask - Keep best-effort governed projection non-blocking for subscriber progress delivery.

    [ ] 9.2.2 Task - Harden replay fallback, resume, and terminal verification
      Ensure product behavior remains deterministic across disconnects, rollout-withheld live delivery, and terminalization.

      [ ] 9.2.2.1 Subtask - Use replay for gap repair, reconnect recovery, and explicit terminal verification instead of transport silence heuristics.
      [ ] 9.2.2.2 Subtask - Preserve typed degraded behavior when live delivery fails after admission or detaches unexpectedly.
      [ ] 9.2.2.3 Subtask - Keep governed terminal materialization tied to explicit terminal handoff plus terminal lookup rather than idle-poll assumptions.

  [ ] 9.3 Section - Phase 9 Integration Tests
    Validate the live-delivery-first conversation bridge under normal, degraded, and recovery conditions before broader runtime-service adoption continues.

    [ ] 9.3.1 Task - Live delivery and subscriber compatibility scenarios
      Verify the product bridge can adopt live turn delivery without changing subscriber-facing UI contracts.

      [ ] 9.3.1.1 Subtask - Add coverage for live subscription admission, incremental event delivery, and stable subscriber translation.
      [ ] 9.3.1.2 Subtask - Add coverage for explicit terminal handoff driving final assistant completion or failure events.
      [ ] 9.3.1.3 Subtask - Add coverage showing governed turn projection failures remain non-blocking for subscriber progress.

    [ ] 9.3.2 Task - Recovery and fallback scenarios
      Verify replay remains the canonical recovery path when live delivery is unavailable or interrupted.

      [ ] 9.3.2.1 Subtask - Add coverage for resume-from-cursor, replay gap repair, and terminal verification after disconnect.
      [ ] 9.3.2.2 Subtask - Add coverage for rollout-withheld or denied live-delivery behavior with typed fallback outcomes.
      [ ] 9.3.2.3 Subtask - Verify traceability across planning, specs, and bridge tests for the live-delivery transport refresh.
