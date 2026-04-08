---
id: jido_code.jido_os_deprecation
status: accepted
date: 2026-04-06
affects:
  - package.jido_code
  - architecture.runtime_service_overlay
  - architecture.agent_os_integration
  - docs.product_foundation
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->
<!-- covers: architecture.runtime_service_overlay.jido_os_is_authority_backed_runtime_services_overlay -->
<!-- covers: architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam -->
<!-- covers: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed -->
<!-- covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts -->
<!-- covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product -->

# Jido OS Integration Deprecation

## Context

`jido_code` previously integrated with `jido_os` as a runtime-services overlay for
coding assistance, external SaaS integration, and session/turn lifecycle management.
This integration was initially designed to leverage `jido_os` as the underlying
runtime while keeping `jido_code` as the product-owned control plane.

However, the integration introduced significant complexity:

1. **Dual-truth problem**: Product state in `jido_code` (ManagedRepo, Run, Evidence)
   had to be synchronized with runtime state in `jido_os` (sessions, turns, bindings).
2. **Runtime coupling**: `jido_code` became tightly coupled to `jido_os` internal
   topology despite public API boundaries.
3. **Maintenance burden**: The local `compat/jido_os` compatibility package required
   ongoing synchronization with the evolving `jido_os` codebase.
4. **Testing complexity**: Integration tests required full runtime bootstrapping,
   making unit testing more difficult.
5. **Dependency overhead**: The `jido_os` dependency and its transitive dependencies
   added significant weight to the `jido_code` package.

## Decision

`jido_code` shall deprecate and remove all `jido_os` integration.

The product will:

1. **Remove `jido_os` dependency** from `mix.exs` and delete the local
   `compat/jido_os` compatibility package.
2. **Remove jido_os-specific gateway modules**:
   - `JidoCode.JidoOsRuntime` - runtime bootstrap and context
   - `JidoCode.RuntimeGateway` - shared runtime service helpers
   - `JidoCode.RuntimeIntegration` - external SaaS integration gateway
   - `JidoCode.Governance.RuntimeIntegrationBridge` - runtime state projection
3. **Remove product-local work-routing boundaries** that depended on `jido_os`
   sessions, turns, or event protocols.
4. **Remove all jido_os-related specs** and update affected architecture decisions.

Future coding assistance and external integration capabilities will be built
directly in `jido_code` using simpler, product-owned patterns rather than
delegating to a separate runtime overlay.

## Consequences

- **Simplified architecture**: `jido_code` becomes a single, self-contained product
  without external runtime dependencies.
- **Reduced complexity**: No need to maintain compatibility packages or synchronize
  state between two systems.
- **Easier testing**: Unit tests can run without bootstrapping a full runtime.
- **Cleaner dependency graph**: Fewer transitive dependencies from `jido_os`.
- **Feature implications**: Any features that depended on `jido_os` (runtime
  state management, delivery lifecycle, external integration bindings) will need to be
  re-implemented or removed.
- **Migration path**: Existing deployments using `jido_os` features will need
  migration guidance (if any exist).

## Removal Timeline

This deprecation is effective immediately. All `jido_os` integration code and
specs will be removed in this commit.

## Replaced Specs

The following specs and ADRs are deprecated by this decision:

- `jido_os_runtime_compatibility.spec.md` - local compatibility package

## Replacement Architecture

Going forward, `jido_code` will:

1. Use `Jido.Runic` (via `ash_jido`) for governed execution authority
2. Implement coding assistance through simpler, direct patterns
3. Handle external integration through product-owned interfaces rather than
   `jido_os` integration services
4. Keep all product truth in Ash resources without external runtime coupling
