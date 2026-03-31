# Jido OS Session Turn Runtime

This subject defines the required `jido_os` coding-assistance turn runtime
contract that `Jido.Code` expects as coding conversations move behind the
product-local `CodingAssistance` boundary.

```spec-meta
id: architecture.jido_os_session_turn_runtime
kind: policy
status: active
summary: Jido.Code depends on `jido_os` coding-assistance sessions owning ordered turns through public turn lifecycle, event, replay, review, query, cancellation, and artifact surfaces while preserving actor-bound context, named policy checks, project scoping, and authority boundaries.
decisions:
  - jido_code.jido_os_session_turn_runtime
  - jido_code.jido_os_public_turn_runtime_adoption
surface:
  - .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  - .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  - compat/jido_os/lib/jido/os/coding_assist/service.ex
  - compat/jido_os/lib/jido/os/session/runtime_agent.ex
  - compat/jido_os/lib/jido/os/session/directory_agent.ex
  - compat/jido_os/lib/jido/os/policy/runtime.ex
  - compat/jido_os/lib/jido/os/state.ex
  - lib/jido_code/coding_assistance.ex
  - lib/jido_code/jido_os_runtime.ex
```

## Requirements

```spec-requirements
- id: architecture.jido_os_session_turn_runtime.session_owns_ordered_turns
  statement: A `jido_os` coding-assistance session shall own the ordered turn history for that coding conversation instead of reducing the session to metadata only.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.public_turn_lifecycle_surface
  statement: `jido_os` shall expose a public turn lifecycle surface with operations equivalent to starting, loading, listing, and cancelling turns without requiring product code to call private agent internals.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.public_turn_event_surface
  statement: `jido_os` shall expose a public event surface for live turn progress and replayable turn history so product code can subscribe to or query emitted turn events through stable public APIs.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.public_turn_replay_supports_incremental_bridge
  statement: Public turn replay shall support incremental, product-bridge-friendly reads of session-owned turn events and terminal summaries so downstream products can translate progress safely without exposing raw runtime or provider-native event protocols directly to UI subscribers.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.turn_outputs_are_first_class_records
  statement: Tool requests, tool results, assistant outputs, and produced artifacts shall be represented as first-class turn records or projections rather than remaining implicit private runtime side effects.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.prior_turn_context_assembly
  statement: New coding-assistance turns shall be able to assemble prompt and execution context from the prior turns owned by the same session.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.actor_bound_context_required
  statement: Public turn operations shall require actor-bound runtime context, including actor, request, correlation, session, and relevant project or workspace identifiers, so security, tracing, and policy remain enforceable.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.authority_boundaries_preserved
  statement: Session authority, directory authority, policy authority, and coding-assistance execution shall remain distinct public boundaries, with product code calling those public authorities instead of mutating session or turn state directly.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.policy_gated_turn_actions
  statement: Turn lifecycle, event access, artifact access, and cancellation actions shall remain subject to named `jido_os` policy checks rather than bypassing the current allow-policy model.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.operator_review_is_bounded_evidence_surface
  statement: Public operator review over one coding turn shall remain a read-only, bounded evidence surface that joins replay, artifact, release, privacy, and guardrail summaries without turning `jido_os` into a product-specific UI layer.
  priority: should
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.project_binding_scopes_repo_turns
  statement: When a coding-assistance turn requires repository scope, the session's project binding shall remain the authoritative scope boundary for that turn.
  priority: must
  stability: evolving

- id: architecture.jido_os_session_turn_runtime.fail_closed_on_scope_or_policy_violation
  statement: Missing session scope, missing required actor context, missing project binding for repo-scoped work, or policy denial shall fail closed instead of falling back to implicit execution.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.jido_os_session_turn_runtime.scenario_bound_session_starts_turn
  covers:
    - architecture.jido_os_session_turn_runtime.session_owns_ordered_turns
    - architecture.jido_os_session_turn_runtime.public_turn_lifecycle_surface
    - architecture.jido_os_session_turn_runtime.public_turn_event_surface
    - architecture.jido_os_session_turn_runtime.turn_outputs_are_first_class_records
    - architecture.jido_os_session_turn_runtime.project_binding_scopes_repo_turns
  given:
    - A coding-assistance session is already bound to a project.
  when:
    - A new coding turn is started for that session.
  then:
    - The turn is recorded under the session, turn events can be observed through a public event surface, and resulting tool activity and artifacts are available as first-class turn outputs.

- id: architecture.jido_os_session_turn_runtime.scenario_prior_turns_shape_next_request
  covers:
    - architecture.jido_os_session_turn_runtime.prior_turn_context_assembly
    - architecture.jido_os_session_turn_runtime.actor_bound_context_required
  given:
    - A coding-assistance session already contains prior turns.
  when:
    - A new turn is created with actor-bound runtime context.
  then:
    - The new turn can assemble execution context from prior turns while preserving actor, request, and correlation metadata.

- id: architecture.jido_os_session_turn_runtime.scenario_policy_or_scope_denial_blocks_execution
  covers:
    - architecture.jido_os_session_turn_runtime.authority_boundaries_preserved
    - architecture.jido_os_session_turn_runtime.policy_gated_turn_actions
    - architecture.jido_os_session_turn_runtime.fail_closed_on_scope_or_policy_violation
  given:
    - A caller lacks required policy permission or repository scope for a coding turn.
  when:
    - The caller attempts to start, inspect, subscribe to, or cancel that turn.
  then:
    - The public authority boundary denies the operation without executing the turn through an implicit private backdoor.

- id: architecture.jido_os_session_turn_runtime.scenario_replay_and_review_support_downstream_bridge_and_governance
  covers:
    - architecture.jido_os_session_turn_runtime.public_turn_replay_supports_incremental_bridge
    - architecture.jido_os_session_turn_runtime.operator_review_is_bounded_evidence_surface
  given:
    - A coding turn has already been started and has emitted public lifecycle events, artifacts, and a terminal outcome.
  when:
    - Product code reads public replay, artifact, and operator-review surfaces for that turn.
  then:
    - The product can bridge those projections into its own subscriber protocol and governance records without coupling UI code to provider-native payloads or treating `jido_os` as the product's durable truth store.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.jido_os_session_turn_runtime.md
  covers:
    - architecture.jido_os_session_turn_runtime.session_owns_ordered_turns
    - architecture.jido_os_session_turn_runtime.public_turn_lifecycle_surface
    - architecture.jido_os_session_turn_runtime.public_turn_event_surface
    - architecture.jido_os_session_turn_runtime.turn_outputs_are_first_class_records
    - architecture.jido_os_session_turn_runtime.prior_turn_context_assembly
    - architecture.jido_os_session_turn_runtime.actor_bound_context_required
    - architecture.jido_os_session_turn_runtime.authority_boundaries_preserved
    - architecture.jido_os_session_turn_runtime.policy_gated_turn_actions
    - architecture.jido_os_session_turn_runtime.project_binding_scopes_repo_turns
    - architecture.jido_os_session_turn_runtime.fail_closed_on_scope_or_policy_violation

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_public_turn_runtime_adoption.md
  covers:
    - architecture.jido_os_session_turn_runtime.public_turn_replay_supports_incremental_bridge
    - architecture.jido_os_session_turn_runtime.operator_review_is_bounded_evidence_surface
```
