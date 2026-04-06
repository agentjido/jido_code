---
id: jido_code.coding_assistance_conversation_driver
status: accepted
date: 2026-03-29
affects:
  - package.jido_code
  - architecture.conversation_driver
  - coding_assistance.boundary
  - docs.product_foundation
---

<!-- covers: architecture.conversation_driver.coding_assistance_is_first_class_driver -->
<!-- covers: architecture.conversation_driver.code_server_routes_through_boundary -->
<!-- covers: architecture.conversation_driver.conversation_identity_maps_to_session -->
<!-- covers: architecture.conversation_driver.actor_context_propagated -->
<!-- covers: architecture.conversation_driver.subscriber_event_contract_preserved -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Coding Assistance Conversation Driver

## Context

`jido_code` has a project-scoped conversation process, event stream, and UI
subscription model. Separately, `JidoCode.CodingAssistance` is a product-local
boundary for coding assistance operations.

Treating coding assistance as merely another LLM adapter would leave actor
propagation, session and project binding, and conversation-to-service identity
mapping spread across multiple layers.

## Decision

`JidoCode.CodingAssistance` shall be the first-class conversation driver
boundary for coding conversations in `Jido.Code`.

Project-scoped conversation entrypoints such as `JidoCode.CodeServer` shall
route coding-assistance turns through `JidoCode.CodingAssistance`.

## Consequences

- Coding assistance operations are centralized behind a product-owned boundary.
- Conversation-to-session identity mapping is preserved.
- Actor context is propagated through the conversation chain.
- The product controls the conversation event contract exposed to UI subscribers.

## Deprecation Note

As of 2026-04-06, this boundary no longer integrates with `jido_os` runtime.
See `jido_code.jido_os_deprecation` for details.
