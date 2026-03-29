# Conversation Driver Architecture

This subject defines the first-class conversation driver architecture for coding
conversations in `Jido.Code`.

```spec-meta
id: architecture.conversation_driver
kind: policy
status: active
summary: Coding conversations center on `JidoCode.CodingAssistance` as the first-class driver boundary while `CodeServer`, UI subscribers, and jido_os session state stay aligned through a stable conversation event contract.
decisions:
  - jido_code.coding_assistance_conversation_driver
surface:
  - .spec/decisions/jido_code.coding_assistance_conversation_driver.md
  - lib/jido_code/code_server.ex
  - lib/jido_code/coding_assistance.ex
  - lib/jido_code_web/live/project_detail_live.ex
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
  given:
    - Conversation subscribers already render assistant stream, final assistant messages, and failure states from the existing event bus.
  when:
    - The coding-assistance driver becomes the primary engine for coding turns.
  then:
    - Subscribers continue to receive the existing conversation event model instead of a second UI-specific protocol.
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
```
