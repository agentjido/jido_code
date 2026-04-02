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
  - jido_code.jido_os_public_turn_live_delivery_adoption
  - jido_code.jido_os_session_turn_runtime
  - jido_code.jido_os_public_turn_runtime_adoption
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
surface:
  - .spec/decisions/jido_code.coding_assistance_conversation_driver.md
  - .spec/decisions/jido_code.jido_os_public_turn_live_delivery_adoption.md
  - .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  - .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  - lib/jido_code/conversations/ingress.ex
  - lib/jido_code/conversations/driver.ex
  - lib/jido_code/conversations/event_bridge.ex
  - lib/jido_code/conversations/turn_bridge.ex
  - lib/jido_code/conversations/policy.ex
  - lib/jido_code/code_server.ex
  - lib/jido_code/coding_assistance.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - test/jido_code/conversations/driver_test.exs
  - test/jido_code/conversations/phase_four_integration_test.exs
  - test/jido_code/conversations/turn_bridge_test.exs
  - test/jido_code/conversations/phase_seven_integration_test.exs
  - test/jido_code/conversations/phase_nine_integration_test.exs
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

- id: architecture.conversation_driver.public_turn_start_is_primary_conversation_path
  statement: Coding conversations shall prefer non-blocking public `jido_os` turn start as the primary runtime execution path, with compatibility-style `assist` kept only as a fallback or migration path rather than the main conversation-driver contract.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.replay_bridge_drives_subscriber_updates
  statement: Once a caller-safe public live-subscription surface is available from `jido_os`, replay shall remain the canonical resume, recovery, gap-repair, and terminal-verification path for the coding conversation driver rather than the preferred steady-state transport for incremental subscriber updates.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
  statement: When public `jido_os` live turn delivery is admitted for a coding conversation, the conversation driver shall prefer `subscribe_turn_events` and provider-neutral live envelopes as the incremental update path while preserving the existing subscriber event contract.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
  statement: The coding conversation driver shall use explicit public terminal handoff and terminal turn lookup to translate completion and failure into stable subscriber events instead of inferring terminal state from polling silence, detach timing, or transport-local heuristics.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.compatibility_assist_is_not_primary_conversation_path
  statement: Compatibility-oriented `assist` responses may remain available for narrow compatibility cases, but product conversation routing shall not depend on one-shot assist envelopes as the primary mechanism for coding turn progress and completion.
  priority: should
  stability: evolving

- id: architecture.conversation_driver.conversation_is_ingress_and_steering_surface
  statement: Operator and repository conversations shall enter the same managed-repository control loop through `jido_os` sessions and turns as ingress and steering surfaces rather than acting as a parallel product control plane.
  priority: must
  stability: evolving

- id: architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context
  statement: Project-detail conversation entry surfaces shall present managed-repository control context while preserving compatibility route shapes and downstream identifiers needed by current `CodeServer` entrypoints during the migration.
  priority: should
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
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
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
    - architecture.conversation_driver.public_turn_start_is_primary_conversation_path
  given:
    - An operator or repo-facing conversation is active for a managed repository.
  when:
    - A coding-oriented turn is admitted through the conversation path.
  then:
    - The turn is treated as ingress and steering input to the same managed-repository control loop rather than as a second product truth lane outside factory governance.

- id: architecture.conversation_driver.scenario_public_turn_live_delivery_bridges_progress_until_terminal
  covers:
    - architecture.conversation_driver.public_turn_start_is_primary_conversation_path
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
    - architecture.conversation_driver.replay_bridge_drives_subscriber_updates
    - architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
    - architecture.conversation_driver.compatibility_assist_is_not_primary_conversation_path
  given:
    - A coding conversation has already been admitted into product-side ingress and policy layers.
  when:
    - The driver starts a non-blocking public `jido_os` turn for that conversation and subscribes to the admitted live-delivery surface.
  then:
    - Incremental progress is expected to reach subscribers through a product-local live bridge over public turn delivery, while replay remains available for resume or recovery and explicit terminal handoff drives stable completion translation instead of a one-shot compatibility assist envelope.

- id: architecture.conversation_driver.scenario_project_detail_route_keeps_conversation_entry_stable
  covers:
    - architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context
  given:
    - Repo detail can be resolved through either a legacy project identifier or a managed-repo identifier during migration.
  when:
    - An operator opens repo detail and starts a conversation from the existing route surface.
  then:
    - The page presents managed-repository context while preserving the compatibility identifier contract needed by current conversation entrypoints.
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
    - architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation

- kind: source_file
  target: lib/jido_code/conversations/turn_bridge.ex
  covers:
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
    - architecture.conversation_driver.replay_bridge_drives_subscriber_updates
    - architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  covers:
    - architecture.conversation_driver.public_jido_os_turn_event_bridge

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  covers:
    - architecture.conversation_driver.public_turn_start_is_primary_conversation_path
    - architecture.conversation_driver.compatibility_assist_is_not_primary_conversation_path

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_public_turn_live_delivery_adoption.md
  covers:
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
    - architecture.conversation_driver.replay_bridge_drives_subscriber_updates
    - architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation

- kind: source_file
  target: lib/jido_code/coding_assistance.ex
  covers:
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path

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

- kind: source_file
  target: test/jido_code/conversations/phase_four_integration_test.exs
  covers:
    - architecture.conversation_driver.code_server_routes_through_boundary
    - architecture.conversation_driver.conversation_identity_maps_to_session
    - architecture.conversation_driver.actor_context_propagated
    - architecture.conversation_driver.subscriber_event_contract_preserved
    - architecture.conversation_driver.public_jido_os_turn_event_bridge
    - architecture.conversation_driver.conversation_is_ingress_and_steering_surface

- kind: source_file
  target: test/jido_code/conversations/turn_bridge_test.exs
  covers:
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
    - architecture.conversation_driver.replay_bridge_drives_subscriber_updates
    - architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation

- kind: source_file
  target: test/jido_code/conversations/phase_seven_integration_test.exs
  covers:
    - architecture.conversation_driver.public_jido_os_turn_event_bridge
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
    - architecture.conversation_driver.replay_bridge_drives_subscriber_updates
    - architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
    - architecture.conversation_driver.subscriber_event_contract_preserved

- kind: source_file
  target: test/jido_code/conversations/phase_nine_integration_test.exs
  covers:
    - architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
    - architecture.conversation_driver.replay_bridge_drives_subscriber_updates
    - architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
    - architecture.conversation_driver.subscriber_event_contract_preserved

- kind: source_file
  target: .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  covers:
    - architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context

- kind: source_file
  target: lib/jido_code/workbench/project_detail.ex
  covers:
    - architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context

- kind: source_file
  target: lib/jido_code_web/live/project_detail_live.ex
  covers:
    - architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context

- kind: source_file
  target: test/jido_code/control/repo_bridge_test.exs
  covers:
    - architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context
```
