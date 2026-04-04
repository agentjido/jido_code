---
id: jido_code.jido_os_public_turn_runtime_adoption
status: accepted
date: 2026-03-31
affects:
  - package.jido_code
  - architecture.conversation_driver
  - architecture.factory_control_plane
  - architecture.execution_pipeline
  - coding_assistance.boundary
  - architecture.jido_os_session_turn_runtime
  - architecture.policy_layers
  - architecture.repo_posture
  - architecture.run_governance
  - jido_os.runtime.compatibility
  - docs.product_foundation
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_driver.public_turn_start_is_primary_conversation_path -->
<!-- covers: architecture.conversation_driver.replay_bridge_drives_subscriber_updates -->
<!-- covers: coding_assistance.boundary.public_turn_wrapper_api -->
<!-- covers: architecture.jido_os_session_turn_runtime.public_turn_replay_supports_incremental_bridge -->
<!-- covers: architecture.jido_os_session_turn_runtime.operator_review_is_bounded_evidence_surface -->
<!-- covers: architecture.factory_control_plane.runtime_turns_feed_governed_control_records -->
<!-- covers: architecture.execution_pipeline.public_turn_materialization_preserves_execution_authority -->
<!-- covers: architecture.policy_layers.public_turn_materialization_preserves_layered_policy -->
<!-- covers: architecture.repo_posture.governed_turn_evidence_can_inform_posture -->
<!-- covers: architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence -->
<!-- covers: jido_os.runtime.compatibility.public_turn_runtime_surface -->
<!-- covers: jido_os.runtime.compatibility.compatibility_assist_uses_same_turn_model -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Jido OS Public Turn Runtime Adoption

## Context

`jido_code` already has the right product seam for coding conversations:

- `CodeServer` owns the project-scoped conversation shell and subscriber contract
- `Conversations.Driver` owns product-side policy and durable ingress
- `CodingAssistance` owns the product-local boundary into public `Jido.Os`
- `jido_os` owns the session and turn runtime

When that seam was first documented, the local `jido_os` surface was still too
thin to run the full conversation cycle behind public turn APIs. As a result,
`jido_code` kept using compatibility-oriented `assist` responses and a
synthetic event bridge that fabricates one assistant delta and one final
assistant message.

That assumption is no longer true. `jido_os` now exposes public turn lifecycle,
read, replay, artifact, cancel, and operator-review surfaces through the coding
assistance service, while keeping actor-bound context, named policy checks, and
project-binding enforcement intact.

At the same time, the improved public turn runtime does not yet provide a
product-ready push protocol that `jido_code` should expose directly to UI
subscribers. The product still needs to preserve its own stable conversation
event contract and keep governed workflow evidence in product truth rather than
leaving review and replay state only in runtime memory.

## Decision

`jido_code` shall adopt the public `jido_os` turn runtime as the primary coding
conversation execution path.

The preferred conversation flow is:

1. `CodeServer` receives the turn and preserves the existing subscriber-facing
   conversation contract.
2. `Conversations.Driver` applies product-side conversation policy and records
   durable ingress into the managed-repository control loop.
3. `CodingAssistance` starts a public `jido_os` turn through the product-owned
   boundary.
4. A product-local replay bridge reads public turn lifecycle, replay, artifact,
   and review projections from `jido_os` and translates them back into the
   stable `jido_code` conversation event model.

Direct compatibility-style `assist` calls may remain available, but they are a
compatibility path, not the primary conversation-driver contract.

`CodingAssistance` shall expose product-local wrappers for the public turn
surface, including turn start, turn read, turn list, turn replay, artifact
read, cancel, and operator review. Higher-level product code shall continue to
talk only to that product-owned boundary instead of assembling raw runtime
requests or calling private `Jido.Os` internals.

Until `jido_os` provides a dedicated public live-subscription surface that is
appropriate for downstream products, `jido_code` shall treat replay as the
authoritative integration path for subscriber updates. The replay bridge may
poll incremental public turn events, but the UI contract remains owned by
`jido_code`.

Workflow and governance surfaces in `jido_code` shall treat terminal turn
outputs as workflow evidence. Public turn read, replay, artifact, and operator
review outputs should be materialized into governed `Run` and `Evidence`
records when product workflow needs durable review, audit, or posture inputs,
rather than assuming the runtime replay store is the long-term product source of
truth.

## Consequences

- `CodingAssistance` needs to grow from an `assist` wrapper into a full
  product-local public turn boundary.
- `Conversations.Driver` should move from blocking compatibility responses to
  non-blocking turn start plus replay-driven subscriber updates.
- `EventBridge` should translate public turn families, terminal summaries,
  failure reason codes, and artifact or review context into the stable
  conversation event model expected by current UI subscribers.
- `CodeServer` will need a turn-bridge worker or equivalent polling mechanism
  so conversation updates continue to arrive through the existing runtime shell
  without coupling UI code to `jido_os` payloads.
- `Run` and `Evidence` projections should eventually capture bounded turn
  review, replay, and artifact outputs when coding conversations produce
  workflow-relevant execution evidence.
