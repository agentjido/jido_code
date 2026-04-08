# Runtime Service Overlay

This subject defines how `Jido.Code` should integrate with the newer
authority-backed runtime-services model in `jido_os` without surrendering
product control-plane ownership.

```spec-meta
id: architecture.runtime_service_overlay
kind: policy
status: deprecated
summary: Jido.Code treats jido_os as an authority-backed runtime-services overlay composed of public service facades and optional admitted capabilities, while product-owned gateways preserve stable product contracts and Ash-backed product truth remains canonical.
superseded_by: architecture.agent_os_integration
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.runtime_evidence_posture_and_rollout_convergence
  - jido_code.jido_os_deprecation
  - jido_code.jido_agent_os_integration
surface:
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - .spec/decisions/jido_code.runtime_evidence_posture_and_rollout_convergence.md
  - .spec/decisions/jido_code.jido_os_deprecation.md
  - .spec/decisions/jido_code.jido_agent_os_integration.md
  - .spec/specs/factory_control_plane.spec.md
  - lib/jido_code/jido_os_runtime.ex
  - lib/jido_code/runtime_gateway.ex
  - lib/jido_code/runtime_integration.ex
  - lib/jido_code/governance/runtime_capability_bridge.ex
  - lib/jido_code/governance/runtime_evidence_bridge.ex
  - lib/jido_code/governance/runtime_evidence_feed.ex
  - lib/jido_code/governance/runtime_integration_bridge.ex
  - lib/jido_code_web/components/operator_state_components.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code_web/live/DashboardRuntimePostureWidget.vue
  - lib/jido_code_web/live/run_detail_live.ex
  - test/jido_code/runtime_gateway_test.exs
  - test/jido_code/runtime_integration_test.exs
  - test/jido_code/governance/runtime_integration_bridge_test.exs
  - test/jido_code/governance/runtime_evidence_bridge_test.exs
  - test/jido_code/governance/runtime_evidence_feed_test.exs
  - test/jido_code/governance/phase_eleven_integration_test.exs
  - test/jido_code/governance/phase_ten_integration_test.exs
  - test/jido_code/governance/runtime_capability_bridge_test.exs
  - test/jido_code/governance/phase_eight_integration_test.exs
  - test/jido_code_web/live/dashboard_live_test.exs
  - test/jido_code_web/live/phase_sixteen_integration_test.exs
  - test/jido_code_web/live/run_detail_live_test.exs
  - test/jido_code_web/live/phase_eleven_integration_test.exs
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
  statement: When Jido.Code adopts public jido_os runtime services, it shall do so through product-owned gateway boundaries such as `JidoCode.RuntimeGateway` and `JidoCode.RuntimeIntegration` so UI, workbench, and control-plane flows stay insulated from provider-neutral runtime payloads and runtime topology churn.
  priority: must
  stability: evolving

- id: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  statement: Runtime-service rollout, denial, degraded-path, replay, and operator-review evidence that affects repository governance or operator trust shall be normalized into product observations, posture, evidence, or decision records instead of remaining UI-local transport knowledge only.
  priority: must
  stability: evolving

- id: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  statement: Operator-facing dashboard and run-detail surfaces shall describe runtime-service posture and degraded-path evidence in product-oriented language that explicitly distinguishes product-owned truth from bounded runtime-service state, and those surfaces shall load through governed run and evidence records instead of workflow-history fallback paths.
  priority: should
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
    - A managed-repository workflow or runtime-service interaction produced rollout, replay, review, or degraded-path runtime evidence.
  when:
    - That evidence changes operator trust, review posture, or execution decisions.
  then:
    - The product is expected to materialize the relevant runtime evidence into its governed control-plane records instead of treating runtime state as the durable source of truth.

- id: architecture.runtime_service_overlay.scenario_operator_surfaces_explain_runtime_rollout_without_transport_leakage
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  given:
    - Governed runtime posture, replay recovery, or rollout evidence affects operator trust or review expectations.
  when:
    - An operator opens dashboard, workbench-adjacent summaries, or governed run detail.
  then:
    - The product presents runtime posture as bounded governance evidence using product-readable language and avoids leaking runtime-native topology or transport implementation details.
    - Hybrid operator summary widgets may improve local filtering or grouping, but they still receive bounded product-authored runtime posture props rather than raw runtime transport envelopes.

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
  target: .spec/decisions/jido_code.jido_os_deprecation.md
  covers:
    - architecture.runtime_service_overlay.jido_os_is_authority_backed_runtime_services_overlay
    - architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
    - architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product

- kind: source_file
  target: lib/jido_code/runtime_gateway.ex
  covers:
    - architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
    - architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product

- kind: source_file
  target: lib/jido_code/runtime_integration.ex
  covers:
    - architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product

- kind: source_file
  target: lib/jido_code/jido_os_runtime.ex
  covers:
    - architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed

- kind: source_file
  target: lib/jido_code/governance/runtime_capability_bridge.ex
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance

- kind: source_file
  target: lib/jido_code/governance/runtime_evidence_bridge.ex
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance

- kind: source_file
  target: lib/jido_code/governance/runtime_evidence_feed.ex
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented

- kind: source_file
  target: lib/jido_code_web/live/DashboardRuntimePostureWidget.vue
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented

- kind: source_file
  target: lib/jido_code/governance/runtime_integration_bridge.ex
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
    - architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary

- kind: source_file
  target: test/jido_code/governance/phase_eight_integration_test.exs
  covers:
    - architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
    - architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance

- kind: source_file
  target: test/jido_code/runtime_integration_test.exs
  covers:
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
    - architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed

- kind: source_file
  target: test/jido_code/governance/runtime_integration_bridge_test.exs
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
    - architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary

- kind: source_file
  target: test/jido_code/governance/runtime_evidence_bridge_test.exs
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance

- kind: source_file
  target: lib/jido_code_web/live/dashboard_live.ex
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product

- kind: source_file
  target: test/jido_code/governance/runtime_evidence_feed_test.exs
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented

- kind: source_file
  target: test/jido_code/governance/phase_eleven_integration_test.exs
  covers:
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented

- kind: source_file
  target: test/jido_code/governance/phase_ten_integration_test.exs
  covers:
    - architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
    - architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
    - architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product

- kind: source_file
  target: test/jido_code_web/live/phase_eleven_integration_test.exs
  covers:
    - architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
    - architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
```
