---
id: jido_code.live_vue_frontend_adoption
status: accepted
date: 2026-04-03
affects:
  - package.jido_code
  - architecture.frontend_stack
  - docs.product_foundation
---

<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge -->
<!-- covers: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling -->
<!-- covers: architecture.frontend_stack.react_is_not_parallel_product_frontend_stack -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->
<!-- covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Live Vue Frontend Adoption

## Context

`jido_code` is still fundamentally a Phoenix product. Its browser surface is
organized around LiveView routes, LiveView state transitions, and
server-authored product control flow. That matches the broader product
architecture: authentication, work orchestration, runtime governance, and
operator-facing product truth all stay in the Elixir application layer.

At the same time, several surfaces are now rich enough that plain HEEx plus
small one-off hooks is no longer the only comfortable UI model. Workbench,
project detail, run detail, dashboard, and other operator surfaces increasingly
need richer client-side component composition.

The repository previously carried an isolated React-based guide surface, but it
was never the product's canonical UI architecture and has since been removed.
Reintroducing React as a broader product layer would recreate the same problem:

- routing and session ownership would remain in LiveView while richer UI drifted
  into a parallel client architecture
- contributor guidance and test strategy would split across incompatible browser
  models
- the product would absorb SPA-like complexity without actually moving product
  truth out of Phoenix

The `live_vue` package is a closer fit for what `jido_code` needs. It keeps
LiveView as the host shell while allowing Vue components to participate in
server-driven props, events, uploads, streams, and SSR-aware rendering through
one bridge surface instead of a separate SPA application.

## Decision

`jido_code` shall standardize on a two-layer browser architecture:

1. Phoenix LiveView remains the canonical product host shell.
2. `live_vue` becomes the canonical rich client-component bridge.

This means:

- LiveView keeps router ownership, authentication and session boundaries,
  server-authored state, form and control flow, and top-level page composition.
- Vue is adopted through `live_vue` for richer interactive components that need
  more client-side composability than plain HEEx or lightweight hooks.
- `live_vue`-compatible Vite and SSR tooling become the standard asset path for
  Vue-backed product surfaces.
- `jido_code` shall not maintain React as a parallel product frontend stack
  once `live_vue` is adopted as the rich-component standard.
- Adoption may be incremental by surface. Existing LiveView-only pages remain
  valid until a richer client component model is justified.
- Browser-facing tests keep LiveView as the routed-surface harness while
  Vue-mounted surfaces should use LiveVue-aware verification rather than
  standalone SPA testing assumptions.

## Consequences

### Positive

- The product keeps its current Phoenix and LiveView control-plane ownership.
- Richer browser UI can be added without splitting the app into a separate SPA.
- SSR, prop diffing, uploads, and event bridging stay aligned with LiveView.
- Contributor guidance can converge on one server-hosted UI model rather than a
  mixture of HEEx, hooks, and unrelated React islands.

### Trade-offs

- The repo will need Vite and SSR tooling alongside the current Phoenix asset
  workflow as implementation progresses.
- Contributors will need explicit conventions for when to stay in plain
  LiveView, when to use hooks, and when to introduce Vue through `live_vue`.
- Browser-facing verification becomes slightly broader because richer surfaces
  need both LiveView and LiveVue-aware testing patterns.

### Non-Goals

- This decision does not turn `jido_code` into a Vue SPA.
- This decision does not remove LiveView from simple routed and form-driven
  surfaces.
- This decision does not change the product-plane/runtime-plane split already
  established in the factory-control-plane and runtime-service-overlay ADRs.
