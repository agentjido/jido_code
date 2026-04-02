---
id: jido_code.runtime_evidence_posture_and_rollout_convergence
status: accepted
date: 2026-04-02
affects:
  - package.jido_code
  - architecture.conversation_driver
  - architecture.execution_pipeline
  - architecture.factory_control_plane
  - architecture.policy_layers
  - architecture.repo_posture
  - architecture.run_governance
  - architecture.runtime_service_overlay
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance -->
<!-- covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth -->
<!-- covers: architecture.repo_posture.governed_turn_evidence_can_inform_posture -->
<!-- covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture -->
<!-- covers: architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence -->
<!-- covers: architecture.policy_layers.public_turn_materialization_preserves_layered_policy -->
<!-- covers: architecture.execution_pipeline.public_turn_materialization_preserves_execution_authority -->
<!-- covers: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path -->

# Runtime Evidence, Posture, and Rollout Convergence

## Context

Phases 8 through 10 established the runtime-service gateway model, live coding
turn delivery, and the product-owned integration gateway over `jido_os`.

That left one important gap:

- runtime capability posture already informed product governance
- governed runs already materialized terminal coding turn output
- integration outcomes already re-entered product observations and events

But the product still lacked one bounded, product-readable way to converge:

- rollout-withheld or denied live coding delivery
- replay fallback or replay-recovery delivery facts
- integration binding health and latest invocation outcomes
- posture-relevant runtime evidence that should influence trust and review

Without that convergence layer, the product risked leaving meaningful runtime
facts split between raw observations, run-local evidence, and UI-local
knowledge.

## Decision

`Jido.Code` shall converge runtime-service evidence back into product-owned
governance records through a bounded runtime-evidence layer.

This means:

1. Runtime-service evidence is product-owned once it matters to governance.
   `jido_os` remains the runtime authority, but rollout, denial, degraded-path,
   replay-recovery, and bounded provider outcome facts that affect review,
   posture, or operator trust must be re-expressed as product observations,
   evidence, and review metadata.

2. Coding-turn delivery facts are governed evidence, not transport trivia.
   When public turn delivery falls back, detaches, or completes through replay
   repair, the product records bounded delivery metadata in governed run
   evidence instead of relying on subscriber transport state as the only trace.

3. Repo posture consumes governed runtime evidence, not raw runtime topology.
   Posture may use bounded runtime-service evidence to shape trust and recovery
   heuristics, but it must continue reading product-owned observations and
   evidence rather than private `jido_os` workers, topics, or transport ids.

4. Product review authority stays product-owned.
   Runtime admission, rollout, or degraded-path status may inform review burden
   and posture, but review, approval, change requests, decisions, and execution
   authority remain governed by product policy, governed runs, and Jido.Runic.

5. Operator-facing rollout narratives stay product-readable.
   Runtime evidence should be summarized in provider-neutral, policy-oriented
   language that preserves joinable repo, run, work-item, session, turn,
   provider, and actor references where they matter, while avoiding raw
   transport payloads or topology leakage.

## Consequences

- `RuntimeEvidenceBridge` becomes the product-owned convergence point for
  bounded runtime capability, integration, and coding-delivery evidence.
- `TurnBridge` and governed run materialization now preserve bounded delivery
  facts so replay fallback and repair paths are explainable after the turn
  finishes.
- `PostureBridge` may lower recovery resilience or otherwise adjust trust using
  product-owned runtime evidence without collapsing product governance into
  runtime policy.
- `RunGovernanceBridge` now carries runtime delivery evidence into evidence,
  review, and decision metadata so operator review stays explainable.
- Dashboard and run-detail operator surfaces now summarize bounded runtime
  posture in product-oriented rollout language instead of relying on runtime
  helper terminology or transport-specific phrasing.
- Phase-level integration coverage now verifies that blocked or degraded runtime
  rollout still leaves dashboard and governed run detail usable for review-safe
  operator workflows.
- The product continues to treat `jido_os` as a runtime overlay and not as the
  durable source of product governance truth.
