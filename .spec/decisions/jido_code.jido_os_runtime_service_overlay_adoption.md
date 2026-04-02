---
id: jido_code.jido_os_runtime_service_overlay_adoption
status: accepted
date: 2026-04-02
affects:
  - package.jido_code
  - architecture.factory_control_plane
  - architecture.runtime_service_overlay
  - coding_assistance.boundary
  - docs.product_foundation
---

<!-- covers: architecture.runtime_service_overlay.jido_os_is_authority_backed_runtime_services_overlay -->
<!-- covers: architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam -->
<!-- covers: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed -->
<!-- covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts -->
<!-- covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance -->
<!-- covers: architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary -->
<!-- covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product -->
<!-- covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth -->
<!-- covers: coding_assistance.boundary.runtime_service_topology_is_opaque_to_product -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Jido OS Runtime Service Overlay Adoption

## Context

Earlier `jido_code` architecture work correctly established two durable ideas:

- `Jido.Code` is a governed software-factory control plane whose durable truth
  lives in product-owned Ash records
- `jido_os` is the runtime and interaction overlay that owns sessions, turns,
  steering, interruption, and runtime capability admission

Those decisions still hold, but `jido_os` has continued to evolve
significantly. It now organizes more of its runtime around:

- an instance-kernel boundary through `InstanceRuntimeSubstrate`
- public service facades over private authority agents and manager-backed
  families
- registry-admitted optional runtime services such as Coding Assistance,
  Integration, Guardrails, PII, Sandbox, and Knowledge Graph
- typed rollout, denial, degraded-path, replay, and audit surfaces that are
  intended to be consumed through public `Jido.Os.*` contracts rather than
  through runtime topology details

At the same time, `jido_os` is still actively migrating internal authority
ownership, including continued work to remove remaining state-owning GenServer
assumptions from session turn execution. That makes one product-side rule more
important than before: `jido_code` must integrate with `jido_os` through stable
public service and authority contracts rather than through assumptions about the
runtime's current internal topology.

## Decision

`Jido.Code` shall treat `jido_os` as an authority-backed runtime-services
overlay, not merely as a special-case coding turn runtime.

This means:

1. Product truth remains in `jido_code`.
   `ManagedRepo`, `Intake`, `Observation`, `Event`, `Assessment`, `WorkItem`,
   `Run`, `Evidence`, `ChangeRequest`, `Decision`, posture records, and similar
   governance objects remain the durable product control plane.

2. Public `Jido.Os.*` facades are the only supported runtime seam.
   `jido_code` may call public coding, session, directory, policy, integration,
   guardrails, privacy, sandbox, knowledge-graph, and similar `Jido.Os.*`
   boundaries when they are documented caller-visible surfaces. Product code
   must not depend on `TurnExecutionController`, pid lookup, signal-bus topics,
   substrate routing metadata, or other private runtime-topology details as
   part of its architecture contract.

3. Optional runtime-service admission is explicit product input.
   Runtime capabilities such as Coding Assistance or Integration may be
   admitted, withheld, unavailable, degraded, or denied with typed outcomes.
   `jido_code` should treat that capability posture as observable control input
   rather than as hidden incidental transport failure.

4. Product-owned gateways preserve product contracts.
   `JidoCode.CodingAssistance` remains the first-class product gateway for
   coding conversations, but it is now understood as one member of a broader
   product-owned runtime gateway layer. Similar product-owned boundaries may be
   introduced for other public runtime services as `jido_code` adopts them.

5. External SaaS runtime operations should compose through the canonical
   runtime integration boundary.
   When `jido_code` needs repo-scoped external SaaS runtime behavior, it should
   compose through public `Jido.Os.Integration.Service` behind a product-owned
   boundary and then normalize those results back into the governed factory loop
   instead of scattering connector-specific runtime logic across setup, UI, or
   webhook-only code paths.

6. Runtime evidence rejoins product governance.
   Rollout state, denial reasons, degraded-path evidence, replay metadata,
   operator-review joins, and other typed runtime outcomes should be captured as
   product observations, evidence, posture signals, or decisions where they
   affect factory governance, rather than remaining UI-local or transport-local
   knowledge.

## Consequences

- The current factory-control-plane direction is reaffirmed rather than
  replaced.
- `jido_code` should not be redesigned around `jido_os` internals, but its ADRs
  and specs should explicitly describe `jido_os` as a runtime-services layer
  with admitted optional services and public authority facades.
- `JidoCode.CodingAssistance` should continue shielding the product from runtime
  topology details, and future runtime-service adoption should follow the same
  product-owned gateway pattern.
- Runtime-service availability, rollout, and degraded-path evidence become
  first-class inputs to product governance and posture, not merely operational
  noise.
- Future integration-service adoption in `jido_code` should use the same model:
  public `jido_os` service boundary underneath, durable product control-plane
  normalization above.
- This is an architectural refresh, not a justification for moving durable
  product truth into `jido_os` or for replacing `Jido.Runic` as the product's
  governed execution authority.
