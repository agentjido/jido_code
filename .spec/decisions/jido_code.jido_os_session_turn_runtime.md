---
id: jido_code.jido_os_session_turn_runtime
status: accepted
date: 2026-03-30
affects:
  - package.jido_code
  - architecture.jido_os_session_turn_runtime
  - architecture.conversation_driver
  - coding_assistance.boundary
  - jido_os.runtime.compatibility
  - docs.product_foundation
---

<!-- covers: architecture.jido_os_session_turn_runtime.session_owns_ordered_turns -->
<!-- covers: architecture.jido_os_session_turn_runtime.public_turn_lifecycle_surface -->
<!-- covers: architecture.jido_os_session_turn_runtime.public_turn_event_surface -->
<!-- covers: architecture.jido_os_session_turn_runtime.turn_outputs_are_first_class_records -->
<!-- covers: architecture.jido_os_session_turn_runtime.prior_turn_context_assembly -->
<!-- covers: architecture.jido_os_session_turn_runtime.actor_bound_context_required -->
<!-- covers: architecture.jido_os_session_turn_runtime.authority_boundaries_preserved -->
<!-- covers: architecture.jido_os_session_turn_runtime.policy_gated_turn_actions -->
<!-- covers: architecture.jido_os_session_turn_runtime.project_binding_scopes_repo_turns -->
<!-- covers: architecture.jido_os_session_turn_runtime.fail_closed_on_scope_or_policy_violation -->
<!-- covers: architecture.conversation_driver.public_jido_os_turn_event_bridge -->
<!-- covers: coding_assistance.boundary.policy_context_propagation -->
<!-- covers: coding_assistance.boundary.public_turn_runtime_boundary -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Jido OS Session-Owned Turn Runtime

## Context

`JidoCode.CodingAssistance` is already the product-owned boundary that starts
or loads a `jido_os` session, binds that session to a project through the
public directory authority, applies AI-preference updates through the public
session authority, and then calls the public coding-assistance service.

Today the local `jido_os` compatibility package is intentionally thin. A
session stores only session metadata, and the coding-assistance service returns
one typed envelope after validating that the session exists. That is sufficient
for wrapper tests, but it is not sufficient for the planned conversation-driver
design where `jido_os` owns the underlying coding runtime while
`jido_code_server` continues to host the local event bus and subscriber shell.

At the same time, `jido_code` already depends on several runtime security and
authorization principles that should not be lost as `jido_os` grows:

- product code talks to public `Jido.Os` authorities instead of private agent internals
- actor, request, correlation, session, project, and workspace context are carried explicitly
- directory authority owns project binding
- policy runtime owns named allow or deny decisions
- missing session scope already fails closed instead of running implicitly

The turn runtime contract needs to become explicit before the underlying
implementation grows, so the eventual `jido_os` turn model strengthens rather
than bypasses those principles.

## Decision

`jido_os` coding-assistance sessions shall become the owners of ordered coding
turns.

The public `Jido.Os` coding-assistance surface shall expose turn lifecycle
operations equivalent to starting, loading, listing, and cancelling turns. The
public surface may evolve within `Jido.Os.CodingAssist.Service` or adjacent
public modules, but product code shall not need private agent-module access to
create, inspect, replay, or cancel turns.

`jido_os` shall expose a public turn-event surface for both live progress and
replayable history. This includes enough event fidelity for assistant deltas,
assistant final messages, tool activity, failures, and produced artifacts to be
projected back into `jido_code`'s existing conversation event model.

Tool requests, tool results, assistant outputs, and artifacts shall be
represented as first-class turn records or public projections rather than as
private side effects hidden behind a final envelope.

New turns shall be able to assemble execution context from prior turns in the
same session, so `conversation_id == session_id` is a real runtime ownership
relationship instead of only a naming convention.

All public turn operations shall remain actor-bound and policy-gated. At
minimum, public turn creation, inspection, event access, artifact access, and
cancellation must continue to carry actor, request, correlation, session, and
project or workspace context needed for tracing and authorization.

The current authority split shall remain intact:

- session authority owns session creation, loading, and AI preferences
- directory authority owns project binding
- policy runtime owns named authorization checks
- coding-assistance execution coordinates turns through public coding-assistance surfaces

Repository-scoped coding turns shall continue to treat the bound project as the
authoritative scope boundary.

Missing session scope, missing required actor context, missing project binding
for repo-scoped work, or policy denial shall fail closed rather than silently
falling back to execution.

## Consequences

- The local compatibility package will eventually need turn storage and public turn-query projections in addition to session metadata.
- The public coding-assistance surface will need operations equivalent to `start_turn`, `get_turn`, `list_turns`, `cancel_turn`, event subscription or replay, and artifact listing or retrieval.
- `assist/3` may remain a convenience entrypoint, but it should become a wrapper over the public turn lifecycle rather than the only contract.
- `JidoCode.CodingAssistance` can stay small and product-owned, but it will need to translate public `jido_os` turn events back into the existing `assistant.delta`, `assistant.message`, and failure events expected by `jido_code_server` subscribers.
- `JidoCode.JidoOsRuntime` will need to seed or document additional named policy actions for turn start, turn read, turn event access, turn cancellation, and artifact access instead of treating those operations as implicit trust.
- Tests should expand from envelope-only assertions to turn history, event replay, artifact records, cancellation semantics, policy denial, and project-binding enforcement.
