# Frontend Architecture

This subject defines the browser technology composition that `jido_code` should
use as it grows beyond plain HEEx-only screens without fragmenting product
ownership across multiple unrelated frontend stacks.

```spec-meta
id: architecture.frontend_stack
kind: policy
status: active
summary: Jido.Code keeps Phoenix LiveView as the routed product host shell while adopting `live_vue` as the canonical bridge for richer client-side Vue components, standardizing on a LiveView-plus-Vue composition model instead of a parallel React or SPA frontend.
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
  - lib/jido_code_web/live/
  - lib/jido_code_web/components/
  - assets/
  - mix.exs
  - config/
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
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - A routed product page needs richer client-side component composition than plain HEEx or lightweight hooks comfortably provide.
  when:
    - The product introduces a richer browser component layer for that page.
  then:
    - LiveView remains the page host shell and the richer client component is expected to arrive through `live_vue` and its aligned tooling rather than through a separate SPA or React island.

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
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: .spec/specs/frontend_architecture.spec.md
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
```
