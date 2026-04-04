# Coding Assistance Boundary

This subject defines the product-local boundary that lets `jido_code` request
coding assistance through the public `jido_os` runtime and session APIs while
giving higher-level conversation drivers a single product-owned integration
surface.

```spec-meta
id: coding_assistance.boundary
kind: feature
status: active
summary: jido_code exposes a product-local coding-assistance boundary that ensures a jido_os instance and session, routes requests through public coding-assistance and authority-facade surfaces, delegates session/project/AI-preference state to canonical jido_os authorities, and keeps higher-level conversation drivers out of runtime topology details while exposing the public turn runtime through product-owned wrappers.
decisions:
  - jido_code.coding_assistance_conversation_driver
  - jido_code.jido_os_runtime_service_overlay_adoption
  - jido_code.jido_os_public_turn_live_delivery_adoption
  - jido_code.jido_os_session_turn_runtime
  - jido_code.jido_os_public_turn_runtime_adoption
surface:
  - lib/jido_code/coding_assistance.ex
  - lib/jido_code/runtime_gateway.ex
  - lib/jido_code/conversations/driver.ex
  - lib/jido_code/jido_os_runtime.ex
  - .spec/decisions/jido_code.jido_os_runtime_service_overlay_adoption.md
  - .spec/decisions/jido_code.jido_os_public_turn_live_delivery_adoption.md
  - .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  - .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  - test/jido_code/coding_assistance_test.exs
  - test/jido_code/governance/phase_eight_integration_test.exs
```

## Requirements

```spec-requirements
- id: coding_assistance.boundary.public_jido_os_service_boundary
  statement: jido_code shall route coding-assistance requests through public `Jido.Os.CodingAssist.Service` and public jido_os authority-facade APIs instead of reaching into private coding agent internals or runtime-topology helpers.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.session_prepared_before_assist
  statement: Coding-assistance requests shall ensure the target jido_os instance and session exist before invoking the coding-assistance service.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.runtime_bootstrap_defaults
  statement: A product-local runtime helper shall bootstrap the embedded jido_os instance and seed development/test defaults for AI runtime descriptors, coding capabilities, allow policies, and additive product-owned runtime gateways without exposing runtime topology details to coding callers.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.session_authority_delegation
  statement: Session lookup, project binding, and session AI-preference updates shall delegate through the canonical jido_os session and directory authorities.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.product_local_driver_api
  statement: The coding-assistance boundary shall expose a product-local API that gathers actor, session, project, collaboration, prompt, and operation shaping so higher-level conversation drivers do not assemble jido_os runtime internals themselves.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.policy_context_propagation
  statement: The coding-assistance boundary shall propagate actor, session, project, request, correlation, and workspace context into public `jido_os` operations so downstream policy and authority checks remain enforceable.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.public_turn_runtime_boundary
  statement: As `jido_os` grows a session-owned turn runtime, the coding-assistance boundary shall use public `jido_os` turn lifecycle, event, query, and cancellation APIs instead of persisting turn state itself or reading private coding agent internals.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.public_turn_wrapper_api
  statement: The coding-assistance boundary shall expose product-local wrappers for public turn start, turn read, turn list, live subscribe, live unsubscribe, turn replay, artifact read, cancellation, and operator review so product callers do not construct raw runtime requests or consume provider-neutral runtime payloads directly.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.live_delivery_ack_and_resume_boundary
  statement: Product-local live subscribe wrappers shall propagate actor, session, project, request, correlation, workspace, and optional resume-cursor context into public `jido_os` live-delivery operations while returning only product-owned acknowledgement data needed by conversation bridges instead of exposing transport-local subscriber details directly.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.replay_and_recovery_wrappers_remain_available
  statement: Even after live delivery is adopted as the preferred incremental update path, the coding-assistance boundary shall keep public replay, turn read, artifact read, and operator-review wrappers available for reconnect recovery, gap repair, rollout-withheld live behavior, and terminal verification.
  priority: must
  stability: evolving

- id: coding_assistance.boundary.runtime_service_topology_is_opaque_to_product
  statement: The coding-assistance boundary shall shield higher-level product code from `jido_os` runtime-topology details such as turn-execution ownership, signal-bus transport, substrate routing metadata, or other private authority wiring, relying only on documented public facades as the product contract.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/coding_assistance.ex
  covers:
    - coding_assistance.boundary.public_jido_os_service_boundary
    - coding_assistance.boundary.session_prepared_before_assist
    - coding_assistance.boundary.session_authority_delegation
    - coding_assistance.boundary.product_local_driver_api
    - coding_assistance.boundary.public_turn_wrapper_api
    - coding_assistance.boundary.live_delivery_ack_and_resume_boundary
    - coding_assistance.boundary.replay_and_recovery_wrappers_remain_available

- kind: source_file
  target: lib/jido_code/jido_os_runtime.ex
  covers:
    - coding_assistance.boundary.runtime_bootstrap_defaults

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  covers:
    - coding_assistance.boundary.public_turn_runtime_boundary

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  covers:
    - coding_assistance.boundary.public_turn_wrapper_api

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_public_turn_live_delivery_adoption.md
  covers:
    - coding_assistance.boundary.public_turn_wrapper_api
    - coding_assistance.boundary.live_delivery_ack_and_resume_boundary
    - coding_assistance.boundary.replay_and_recovery_wrappers_remain_available

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_runtime_service_overlay_adoption.md
  covers:
    - coding_assistance.boundary.runtime_service_topology_is_opaque_to_product

- kind: source_file
  target: lib/jido_code/conversations/driver.ex
  covers:
    - coding_assistance.boundary.policy_context_propagation

- kind: source_file
  target: test/jido_code/coding_assistance_test.exs
  covers:
    - coding_assistance.boundary.public_jido_os_service_boundary
    - coding_assistance.boundary.session_prepared_before_assist
    - coding_assistance.boundary.session_authority_delegation
    - coding_assistance.boundary.public_turn_wrapper_api
    - coding_assistance.boundary.live_delivery_ack_and_resume_boundary
    - coding_assistance.boundary.replay_and_recovery_wrappers_remain_available

- kind: command
  target: mix test test/jido_code/coding_assistance_test.exs
  covers:
    - coding_assistance.boundary.public_jido_os_service_boundary
    - coding_assistance.boundary.session_prepared_before_assist
    - coding_assistance.boundary.runtime_bootstrap_defaults
    - coding_assistance.boundary.session_authority_delegation

- kind: source_file
  target: test/jido_code/governance/phase_eight_integration_test.exs
  covers:
    - coding_assistance.boundary.public_jido_os_service_boundary
    - coding_assistance.boundary.runtime_bootstrap_defaults
    - coding_assistance.boundary.product_local_driver_api
```
