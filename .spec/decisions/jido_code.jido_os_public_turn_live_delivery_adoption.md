---
id: jido_code.jido_os_public_turn_live_delivery_adoption
status: accepted
date: 2026-04-01
affects:
  - package.jido_code
  - architecture.conversation_driver
  - coding_assistance.boundary
  - architecture.jido_os_session_turn_runtime
  - docs.product_foundation
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path -->
<!-- covers: architecture.conversation_driver.replay_bridge_drives_subscriber_updates -->
<!-- covers: architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation -->
<!-- covers: architecture.factory_control_plane.runtime_turns_feed_governed_control_records -->
<!-- covers: coding_assistance.boundary.public_turn_wrapper_api -->
<!-- covers: coding_assistance.boundary.live_delivery_ack_and_resume_boundary -->
<!-- covers: coding_assistance.boundary.replay_and_recovery_wrappers_remain_available -->
<!-- covers: architecture.jido_os_session_turn_runtime.public_turn_live_subscription_surface -->
<!-- covers: architecture.jido_os_session_turn_runtime.live_delivery_resume_has_stable_cursor_and_terminal_handoff -->
<!-- covers: architecture.jido_os_session_turn_runtime.live_and_replay_release_parity -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Jido OS Public Turn Live Delivery Adoption

## Context

The prior public-turn adoption decision in
`jido_code.jido_os_public_turn_runtime_adoption` correctly moved `jido_code`
toward public `jido_os` turn lifecycle and replay surfaces, but it was written
while downstream products still lacked a caller-safe live-delivery API.

That gap is now closed in `jido_os`.

The public coding-assistance surface now exposes additive live turn delivery
through `subscribe_turn_events` and `unsubscribe_turn_events`, with:

- explicit policy-gated live subscription admission
- provider-neutral live-delivery acknowledgements
- stable resumable cursors anchored to replay ordering
- replay join and terminal lookup metadata
- explicit terminal-handoff envelopes instead of silence-based completion
- rollout, denial, detachment, and failure outcomes that stay typed and
  provider-neutral

This means `jido_code` no longer needs to treat replay polling as the preferred
steady-state transport for coding-conversation progress. At the same time,
`jido_code` still owns the subscriber-facing conversation contract, and replay
remains the durable recovery authority for reconnect, gap repair, and terminal
verification.

## Decision

`jido_code` shall adopt public `jido_os` live turn delivery as the preferred
incremental update path for coding conversations.

The preferred flow is now:

1. `CodeServer` admits the turn and preserves the existing subscriber-facing
   conversation contract.
2. `Conversations.Driver` applies product-side policy and durable ingress, then
   starts a public `jido_os` turn.
3. `CodingAssistance` exposes product-local wrappers for live subscribe,
   unsubscribe, replay, read, artifact, cancel, and operator-review surfaces.
4. A product-owned bridge subscribes to the public live turn stream and
   translates provider-neutral live envelopes into the stable `jido_code`
   conversation event model.
5. Replay remains available and authoritative for resume, reconnect recovery,
   gap repair, rollout-withheld live behavior, and explicit terminal
   verification.

`jido_code` shall not expose raw `jido_os` transport topics, raw signal-bus
messages, or provider-neutral live envelopes directly to UI subscribers.
Live-delivery acknowledgements, resume cursors, replay joins, and terminal
handoff metadata remain product-owned bridge inputs, not UI protocols.

Conversation completion shall not be inferred from polling silence or transport
detachment alone. Product bridges should use explicit public terminal handoff
and terminal turn lookup to drive stable assistant completion or failure events.

## Consequences

- `CodingAssistance` must grow from replay-oriented public-turn wrappers into a
  full product-local live-delivery and recovery boundary.
- `CodeServer` and the conversation bridge should prefer live subscription for
  incremental progress while preserving replay as the canonical recovery path.
- `EventBridge` should translate explicit public terminal handoff into the same
  stable subscriber completion semantics already used by product UI consumers.
- Live-delivery rollout, denial, detach, and failure outcomes must stay typed at
  the product bridge so `jido_code` can recover deterministically instead of
  silently falling back through implicit private behavior.
- Governed product truth still lives in `Run`, `Evidence`, and adjacent product
  records; public live delivery improves transport and recovery semantics but
  does not replace product-owned durable workflow evidence.

## Current Truth

Phase 9.1 now lands the first product-local live-delivery boundary in this repo:

- `JidoCode.CodingAssistance` exposes public live subscribe and unsubscribe
  wrappers alongside replay, read, artifact, cancel, and review wrappers.
- The repo-local compatibility `jido_os` package exposes additive public
  subscribe and unsubscribe surfaces plus provider-neutral terminal handoff.
- Product-local live acknowledgements normalize resume cursor, replay join,
  terminal snapshot, and detach metadata before the conversation bridge adopts
  live delivery as its preferred incremental path.

Phase 9.2 now lands the live-delivery-first conversation bridge:

- `JidoCode.Conversations.TurnBridge` now prefers admitted public live delivery
  for steady-state incremental updates and falls back to replay only for
  degraded admission, recovery, gap repair, or timeout repair.
- `JidoCode.Conversations.EventBridge` now translates explicit terminal handoff
  into stable final assistant or failure events instead of relying on silence
  or idle-poll assumptions.
- Governed terminal materialization stays best-effort and non-blocking for
  subscriber progress while replay remains the canonical verification and
  terminal-lookup path.

Phase 9.3 now adds end-to-end product coverage for the live bridge:

- Integration coverage exercises live subscription admission, incremental event
  delivery, explicit terminal handoff, replay cursor repair after detachment,
  and rollout-withheld fallback through the `CodeServer -> Driver -> TurnBridge`
  path.
- The same integration suite verifies that governed projection failures remain
  typed and non-blocking for subscriber-visible progress and completion.
