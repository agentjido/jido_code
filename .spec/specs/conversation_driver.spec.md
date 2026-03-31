# Conversation Driver Architecture

This subject defines the first-class conversation driver architecture for coding
conversations in `Jido.Code`.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.conversation_driver
kind: policy
status: active
summary: Coding conversations center on `JidoCode.CodingAssistance` as the first-class driver boundary while `CodeServer`, UI subscribers, and jido_os session state stay aligned through a stable conversation event contract.
decisions:
  - jido_code.coding_assistance_conversation_driver
  - jido_code.jido_os_session_turn_runtime
  - jido_code.factory_control_plane_and_runtime_overlay
surface:
  - .spec/decisions/jido_code.coding_assistance_conversation_driver.md
  - .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - lib/jido_code/conversations/ingress.ex
  - lib/jido_code/conversations/driver.ex
  - lib/jido_code/conversations/event_bridge.ex
  - lib/jido_code/conversations/policy.ex
  - lib/jido_code/code_server.ex
  - lib/jido_code/coding_assistance.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - test/jido_code/conversations/driver_test.exs
```

## Requirements

```spec-requirements
- id: architecture.conversation_driver.coding_assistance_is_first_class_driver
  statement: `JidoCode.CodingAssistance` shall be the first-class product conversation driver boundary for coding conversations rather than a hidden downstream helper behind a generic LLM-adapter slot.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.code_server_routes_through_boundary
  statement: Project-scoped conversation entrypoints shall route coding-assistance turns through `JidoCode.CodingAssistance` instead of coupling UI or `CodeServer` directly to jido_os internals.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.conversation_identity_maps_to_session
  statement: Conversation identity shall align `conversation_id` with the coding-assistance `session_id`, while `project_id` remains the binding used to scope that session.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.actor_context_propagated
  statement: The conversation path shall propagate the initiating actor and request context before coding-assistance execution begins.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.subscriber_event_contract_preserved
  statement: The coding-assistance conversation driver shall translate service responses back into the existing conversation event model so subscriber-facing UI integrations remain stable while the driver changes.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.public_jido_os_turn_event_bridge
  statement: The coding-assistance conversation driver shall consume public `jido_os` session-turn lifecycle, event, and artifact surfaces and translate them into the existing conversation event model instead of coupling subscribers to `jido_os`-native payloads.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.conversation_is_ingress_and_steering_surface
  statement: Operator and repository conversations shall enter the same managed-repository control loop through `jido_os` sessions and turns as ingress and steering surfaces rather than acting as a parallel product control plane.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.conversation_driver.scenario_turn_routes_through_coding_assistance
  covers:
    - architecture.conversation_driver.coding_assistance_is_first_class_driver
    - architecture.conversation_driver.code_server_routes_through_boundary
    - architecture.conversation_driver.conversation_identity_maps_to_session
    - architecture.conversation_driver.actor_context_propagated
  given:
    - A project conversation is active for a managed repository.
  when:
    - A user sends a coding-oriented conversation turn.
  then:
    - The conversation path carries actor and request context, uses the conversation identity as the coding-assistance session identity, and routes the turn through `JidoCode.CodingAssistance` before any jido_os service call occurs.

- id: architecture.conversation_driver.scenario_existing_ui_event_contract_survives_driver_swap
  covers:
    - architecture.conversation_driver.subscriber_event_contract_preserved
    - architecture.conversation_driver.public_jido_os_turn_event_bridge
  given:
    - Conversation subscribers already render assistant stream, final assistant messages, and failure states from the existing event bus.
  when:
    - The coding-assistance driver becomes the primary engine for coding turns.
  then:
    - Subscribers continue to receive the existing conversation event model instead of a second UI-specific protocol.

- id: architecture.conversation_driver.scenario_conversation_enters_factory_loop
  covers:
    - architecture.conversation_driver.code_server_routes_through_boundary
    - architecture.conversation_driver.conversation_is_ingress_and_steering_surface
  given:
    - An operator or repo-facing conversation is active for a managed repository.
  when:
    - A coding-oriented turn is admitted through the conversation path.
  then:
    - The turn is treated as ingress and steering input to the same managed-repository control loop rather than as a second product truth lane outside factory governance.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.coding_assistance_conversation_driver.md
  covers:
    - architecture.conversation_driver.coding_assistance_is_first_class_driver
    - architecture.conversation_driver.code_server_routes_through_boundary
    - architecture.conversation_driver.conversation_identity_maps_to_session
    - architecture.conversation_driver.actor_context_propagated
    - architecture.conversation_driver.subscriber_event_contract_preserved

- kind: source_file
  target: lib/jido_code/conversations/driver.ex
  covers:
    - architecture.conversation_driver.code_server_routes_through_boundary
    - architecture.conversation_driver.conversation_identity_maps_to_session
    - architecture.conversation_driver.actor_context_propagated

- kind: source_file
  target: lib/jido_code/conversations/event_bridge.ex
  covers:
    - architecture.conversation_driver.subscriber_event_contract_preserved
    - architecture.conversation_driver.public_jido_os_turn_event_bridge

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  covers:
    - architecture.conversation_driver.public_jido_os_turn_event_bridge

- kind: source_file
  target: .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  covers:
    - architecture.conversation_driver.conversation_is_ingress_and_steering_surface

- kind: source_file
  target: lib/jido_code/conversations/ingress.ex
  covers:
    - architecture.conversation_driver.conversation_is_ingress_and_steering_surface

- kind: source_file
  target: test/jido_code/conversations/driver_test.exs
  covers:
    - architecture.conversation_driver.code_server_routes_through_boundary
    - architecture.conversation_driver.conversation_identity_maps_to_session
    - architecture.conversation_driver.actor_context_propagated
    - architecture.conversation_driver.subscriber_event_contract_preserved
    - architecture.conversation_driver.public_jido_os_turn_event_bridge
```
