# Phase 12 - Live Vue Toolchain and Host Shell Foundation

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/frontend_architecture.spec.md`
- `../specs/developer_workflow.spec.md`
- `../specs/package_quality_standards.spec.md`
- `../specs/product_foundation_docs.spec.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `mix.exs`
- `config/`
- `assets/`
- `lib/jido_code_web.ex`
- `lib/jido_code_web/components/`
- `lib/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 1 through 11 are complete and established the current Phoenix, LiveView, and runtime-service architecture.
- The repo has already removed the earlier React-specific guide surface and no longer treats React as a product frontend stack.
- LiveView remains the routed product host shell, and `live_vue` is being added as the canonical bridge for richer client-side components rather than as a SPA replacement.

[x] 12 Phase 12 - Live Vue Toolchain and Host Shell Foundation
  Establish the dependency, asset, SSR, and host-shell baseline required for `live_vue` so richer Vue components can be introduced without changing LiveView’s ownership of routes, sessions, or server-authored state.

  [x] 12.1 Section - Dependency and Asset Pipeline Baseline
    Introduce the `live_vue`-aligned browser toolchain in a way that is explicit, reproducible, and compatible with the repo’s current Phoenix contributor workflow.

    [x] 12.1.1 Task - Add the `live_vue` dependency and supporting asset tooling
      Make the package and build surfaces ready for Vue-backed components while keeping the repo’s Mix-first contributor model intact.

      [x] 12.1.1.1 Subtask - Add `live_vue` and any required Phoenix/Vite integration dependencies to the Mix surface.
      [x] 12.1.1.2 Subtask - Introduce the Vite-oriented asset structure and configuration expected by `live_vue` without reintroducing the removed React/npm surface patterns.
      [x] 12.1.1.3 Subtask - Keep setup, build, and deploy commands legible through the repo’s canonical Mix and Phoenix entrypoints.

    [x] 12.1.2 Task - Introduce SSR-capable baseline configuration
      Prepare the project for Vue-backed SSR where appropriate while keeping that capability bounded behind product-owned configuration choices.

      [x] 12.1.2.1 Subtask - Add environment-aware `live_vue` and SSR configuration in the Phoenix config surface.
      [x] 12.1.2.2 Subtask - Keep development and production defaults explicit so local contributor workflow stays understandable.
      [x] 12.1.2.3 Subtask - Preserve a safe fallback path for routes that remain plain LiveView while the richer stack is rolling out incrementally.

  [x] 12.2 Section - Phoenix Host Shell and Layout Integration
    Connect the new frontend toolchain to the existing product shell without changing route ownership or creating a parallel SPA entrypoint.

    [x] 12.2.1 Task - Wire Live Vue into the Phoenix web layer
      Make Vue-backed components available through the same Phoenix and LiveView shell that already owns product routes.

      [x] 12.2.1.1 Subtask - Add the LiveVue helper/import surface to the shared web layer and component namespaces.
      [x] 12.2.1.2 Subtask - Update layouts and root asset loading so LiveVue and Vite assets load through the normal product shell rather than an isolated page entry.
      [x] 12.2.1.3 Subtask - Preserve route, auth, and session ownership in LiveView and Phoenix while ensuring Vue components mount as bounded sub-surfaces.

    [x] 12.2.2 Task - Define the initial host-shell mounting rules
      Set the baseline product rule for where Vue is allowed to live and where plain LiveView remains the right default.

      [x] 12.2.2.1 Subtask - Document and encode that routed product pages are still LiveView-owned host shells.
      [x] 12.2.2.2 Subtask - Define the allowed mounting pattern for Vue-backed components inside LiveView templates and shared HEEx components.
      [x] 12.2.2.3 Subtask - Avoid introducing duplicate client boot paths, route-side SPA hydration assumptions, or direct runtime-topology leakage into the browser layer.

  [x] 12.3 Section - Phase 12 Integration Tests
    Validate the toolchain and host-shell foundation before product surfaces start migrating onto the new frontend stack.

    [x] 12.3.1 Task - Toolchain and host boot scenarios
      Verify the project can start, build, and render the new browser layer without changing the routed LiveView shell.

      [x] 12.3.1.1 Subtask - Add coverage for dependency setup, asset build, and host-shell boot paths with the new LiveVue baseline in place.
      [x] 12.3.1.2 Subtask - Add coverage showing plain LiveView routes still render correctly when no Vue-backed component is mounted.
      [x] 12.3.1.3 Subtask - Verify spec, docs, and contributor-surface traceability stay aligned with the new frontend toolchain baseline.
