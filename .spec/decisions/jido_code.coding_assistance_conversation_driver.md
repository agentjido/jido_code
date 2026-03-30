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

`jido_code` already has two relevant layers. `JidoCode.CodeServer` and the
`jido_code_server` dependency provide the current project-scoped conversation
process, event stream, and UI subscription model. Separately,
`JidoCode.CodingAssistance` is a product-local boundary that boots the embedded
`jido_os` instance, ensures a session exists, binds project and AI-preference
state through public runtime agents, and calls the public
`Jido.Os.CodingAssist.Service`.

Today those layers are not yet joined. The current conversation flow still uses
the generic `jido_code_server` LLM/tool loop directly, while the
coding-assistance service boundary exists beside it. Treating coding assistance
as merely another LLM adapter would leave actor propagation, session and project
binding, and conversation-to-service identity mapping spread across multiple
layers. It would also couple UI and runtime code to internal `Jido.Os` concerns
instead of keeping that contract behind a product-local boundary.

The local `jido_os` compatibility package is still intentionally thin, so the
integration contract needs to be recorded before the full assistant runtime
behavior exists.

## Decision

`JidoCode.CodingAssistance` shall be the first-class conversation driver
boundary for coding conversations in `Jido.Code`.

Project-scoped conversation entrypoints such as `JidoCode.CodeServer` shall
route coding-assistance turns through `JidoCode.CodingAssistance` rather than
calling `Jido.Os` internals directly or hiding the integration behind a generic
LLM-adapter slot.

Conversation identity shall align with coding-assistance session identity. A
conversation's `conversation_id` is the stable `session_id` used for
coding-assistance calls, while `project_id` remains the project binding for that
session.

The conversation path shall propagate the initiating actor and request context
before assistance execution begins. At minimum this includes `actor_id`,
`project_id`, `conversation_id` or `session_id`, and request or correlation
metadata needed for tracing and policy.

The coding-assistance driver shall translate service responses back into the
existing conversation event model used by subscribers and UI code. Changing the
driver must not require a second UI-specific protocol when the existing
`assistant.delta`, `assistant.message`, and failure events are sufficient.

## Consequences

- `CodeServer` and UI entrypoints need actor-aware conversation APIs instead of
  anonymous message sends.
- The `jido_code_server` conversation runtime becomes the host process and event
  envelope, while `JidoCode.CodingAssistance` becomes the primary driver for
  coding turns.
- Session bootstrap, project binding, and AI-preference management stay
  concentrated in the product-local boundary instead of leaking into LiveView or
  generic runtime plumbing.
- The mapping from conversation state to coding-assistance request shape becomes
  an explicit adapter concern, including objective extraction, prompt variables,
  collaboration state, and tool intent.
- The thin local `jido_os` compatibility surface can continue to satisfy tests
  while richer assistant behavior lands incrementally behind the same boundary.
