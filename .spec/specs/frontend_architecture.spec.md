# Frontend Architecture

This subject defines the browser technology composition that `jido_code` should
use as it grows beyond plain HEEx-only screens without fragmenting product
ownership across multiple unrelated frontend stacks.

```spec-meta
id: architecture.frontend_stack
kind: policy
status: active
summary: Jido.Code keeps Phoenix LiveView as the routed product host shell while adopting `live_vue` as the canonical bridge for richer client-side Vue components, standardizing on a LiveView-plus-Vue composition model with a product-owned mounting boundary and LiveVue-aware test helpers instead of a parallel React or SPA frontend, beginning with bounded operator summary surfaces before deeper workflow pages.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.live_vue_frontend_adoption
surface:
  - .spec/decisions/jido_code.live_vue_frontend_adoption.md
  - .spec/specs/frontend_architecture.spec.md
  - .spec/specs/package.spec.md
  - .spec/specs/product_foundation_docs.spec.md
  - lib/jido_code_web/router.ex
  - lib/jido_code_web.ex
  - lib/jido_code_web/components/live_vue_components.ex
  - lib/jido_code_web/live/
  - lib/jido_code_web/components/
  - assets/
  - mix.exs
  - config/
  - test/support/live_vue_case.ex
  - test/jido_code_web/components/
  - test/jido_code_web/live/
```

## Requirements

```spec-requirements
- id: architecture.frontend_stack.liveview_remains_product_host_shell
  statement: Routed browser product surfaces shall keep Phoenix LiveView as the canonical host shell for router ownership, authentication and session boundaries, server-authored state, and page composition rather than being replaced by a separate SPA frontend.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  statement: Rich interactive browser components shall standardize on Vue mounted through `live_vue` so client-side components participate in LiveView props, events, uploads, and stream-driven updates instead of relying on ad hoc client islands or an unrelated React surface.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.product_owned_mounting_boundary
  statement: Vue-backed product surfaces shall mount through a product-owned helper boundary that standardizes component naming, prop delivery, stream delivery, and emit-to-LiveView event wiring instead of scattering raw LiveVue attribute conventions across individual pages.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.server_authored_props_streams_and_events
  statement: The LiveView shell shall remain the source of truth for server-authored browser state, with bounded props, top-level streams, uploads, and explicit event handoff rules crossing into Vue while ephemeral client-only state remains presentation-local.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
  statement: Once Vue-backed surfaces are adopted, the canonical browser asset path for those surfaces shall use the `live_vue`-aligned Vite and SSR toolchain rather than a React-specific or one-off client build path.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
  statement: `jido_code` shall not maintain React as a parallel product frontend technology stack after `live_vue` is chosen as the standard rich-component bridge.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.adoption_is_incremental_per_surface
  statement: The product may adopt `live_vue` incrementally on the surfaces that justify richer client composition while leaving simpler LiveView-only routes and forms on plain HEEx where that remains the clearer implementation.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  statement: Browser-facing verification shall keep LiveView tests as the primary routed-surface harness and should add LiveVue-aware test helpers for Vue-mounted surfaces instead of assuming a standalone SPA testing model.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.frontend_stack.scenario_rich_surface_needs_client_composability
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - A routed product page needs richer client-side component composition than plain HEEx or lightweight hooks comfortably provide.
  when:
    - The product introduces a richer browser component layer for that page.
  then:
    - LiveView remains the page host shell and the richer client component is expected to arrive through `live_vue` and its aligned tooling rather than through a separate SPA or React island.

- id: architecture.frontend_stack.scenario_hybrid_surface_uses_shared_boundary
  covers:
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  given:
    - A LiveView-owned product surface needs a richer Vue-backed island.
  when:
    - The surface mounts that island and wires events back into LiveView.
  then:
    - The mount uses the shared product boundary, server-owned data stays bounded in props or streams, and test helpers can inspect the Vue contract without replacing the normal LiveView test harness.

- id: architecture.frontend_stack.scenario_simple_surface_stays_plain_liveview
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - A product route remains mostly form-driven or server-rendered.
  when:
    - That route does not need richer client-side composition.
  then:
    - The route may remain a plain LiveView or HEEx surface without being forced into Vue unnecessarily.

- id: architecture.frontend_stack.scenario_operator_summary_route_adopts_bounded_vue_widget
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - An operator-facing route such as dashboard or settings benefits from richer summary grouping or client-local filtering.
  when:
    - The route adopts a bounded Vue-backed widget for that summary region.
  then:
    - The route stays LiveView-owned, server-authored props remain bounded, and the Vue-backed region augments rather than replaces the routed product shell.

- id: architecture.frontend_stack.scenario_frontend_stack_does_not_re_fragment
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  given:
    - Contributors need a standard way to build and verify richer browser UI.
  when:
    - The repository documents or implements that richer UI path.
  then:
    - The standard stack remains LiveView plus `live_vue`, and testing/documentation do not reintroduce React or SPA assumptions as a second frontend model.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.live_vue_frontend_adoption.md
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: .spec/specs/frontend_architecture.spec.md
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: lib/jido_code_web/components/live_vue_components.ex
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/support/live_vue_case.ex
  covers:
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: lib/jido_code_web/live/DashboardRunSummaryWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/DashboardRuntimePostureWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/SettingsOverviewWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/jido_code_web/live/security_settings_live_test.exs
  covers:
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/jido_code_web/components/live_vue_components_test.exs
  covers:
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: test/jido_code_web/live/phase_thirteen_integration_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
```
