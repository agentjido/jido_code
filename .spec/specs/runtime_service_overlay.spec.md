# Runtime Service Overlay

This subject defines how `Jido.Code` should integrate with the newer
authority-backed runtime-services model in `jido_os` without surrendering
product control-plane ownership.

```spec-meta
id: architecture.runtime_service_overlay
kind: policy
status: active
summary: Jido.Code treats jido_os as an authority-backed runtime-services overlay composed of public service facades and optional admitted capabilities, while product-owned gateways preserve stable product contracts and Ash-backed product truth remains canonical.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.jido_os_runtime_service_overlay_adoption
  - jido_code.jido_os_public_turn_live_delivery_adoption
  - jido_code.jido_os_public_turn_runtime_adoption
surface:
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - .spec/decisions/jido_code.jido_os_runtime_service_overlay_adoption.md
  - .spec/decisions/jido_code.jido_os_public_turn_live_delivery_adoption.md
  - .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  - .spec/specs/factory_control_plane.spec.md
  - .spec/specs/coding_assistance_boundary.spec.md
  - lib/jido_code/jido_os_runtime.ex
  - lib/jido_code/coding_assistance.ex
  - lib/jido_code/conversations/driver.ex
  - lib/jido_code/conversations/turn_bridge.ex
```

## Requirements

```spec-requirements
- id: architecture.runtime_service_overlay.jido_os_is_authority_backed_runtime_services_overlay
  statement: Jido.Code shall treat `jido_os` as an authority-backed runtime-services overlay with public service facades over private runtime authorities rather than as a product-owned durable control plane or a one-off coding helper.
  priority: must
  stability: evolving

- id: architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
  statement: Product architecture shall depend only on documented public `Jido.Os.*` service and authority facades for runtime behavior and shall not treat pid lookup, substrate routing metadata, private workers, raw signal-bus topics, or other runtime-topology details as product contracts.
  priority: must
  stability: evolving

- id: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
  statement: Optional runtime capabilities such as coding assistance, integration, guardrails, privacy, sandbox, or knowledge-graph services shall be treated as explicitly admitted, withheld, denied, unavailable, or degraded runtime surfaces with typed outcomes rather than as implicitly always-on product dependencies.
  priority: must
  stability: evolving

- id: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  statement: When Jido.Code adopts public jido_os runtime services, it shall do so through product-owned gateway boundaries such as `JidoCode.CodingAssistance` so UI, workbench, and control-plane flows stay insulated from provider-neutral runtime payloads and runtime topology churn.
  priority: must
  stability: evolving

- id: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  statement: Runtime-service rollout, denial, degraded-path, replay, and operator-review evidence that affects repository governance or operator trust shall be normalized into product observations, posture, evidence, or decision records instead of remaining UI-local transport knowledge only.
  priority: must
  stability: evolving

- id: architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
  statement: Repo-scoped external SaaS runtime behavior should compose through the canonical public `Jido.Os.Integration.Service` behind product-owned boundaries rather than scattering connector-specific runtime logic across product setup, webhook, or UI surfaces.
  priority: should
  stability: evolving

- id: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  statement: Ongoing internal runtime migrations inside jido_os, including authority-family reshaping or turn-execution ownership changes, shall not require Jido.Code to change its product architecture so long as the documented public `Jido.Os.*` contracts remain stable.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.runtime_service_overlay.scenario_product_gateway_hides_runtime_topology
  covers:
    - architecture.runtime_service_overlay.jido_os_is_authority_backed_runtime_services_overlay
    - architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  given:
    - jido_os continues evolving its internal authority and transport topology.
  when:
    - Jido.Code starts or monitors runtime work through product-owned gateway boundaries.
  then:
    - The product architecture depends on stable public runtime facades and keeps runtime topology details out of UI, workbench, and control-plane contracts.

- id: architecture.runtime_service_overlay.scenario_optional_runtime_capability_is_withheld_or_denied
  covers:
    - architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  given:
    - A runtime capability is unavailable, rollout-withheld, policy-denied, or degraded for a managed repository interaction.
  when:
    - Jido.Code attempts to use that runtime capability through its product-owned gateway.
  then:
    - The result remains typed and can feed product governance, posture, or evidence rather than collapsing into an implicit private fallback.

- id: architecture.runtime_service_overlay.scenario_runtime_evidence_rejoins_factory_governance
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  given:
    - A managed-repository workflow or conversation produced rollout, replay, review, or degraded-path runtime evidence.
  when:
    - That evidence changes operator trust, review posture, or execution decisions.
  then:
    - The product is expected to materialize the relevant runtime evidence into its governed control-plane records instead of treating runtime state as the durable source of truth.

- id: architecture.runtime_service_overlay.scenario_external_runtime_integration_composes_through_canonical_service
  covers:
    - architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  given:
    - A managed repository needs repo-scoped external SaaS runtime behavior.
  when:
    - Jido.Code adopts that runtime capability.
  then:
    - The product composes through the canonical public integration boundary behind a product-owned gateway and normalizes the resulting outcomes back into the governed factory loop.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.jido_os_runtime_service_overlay_adoption.md
  covers:
    - architecture.runtime_service_overlay.jido_os_is_authority_backed_runtime_services_overlay
    - architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
    - architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
    - architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
```
