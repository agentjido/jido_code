# Phase 13 - Live Vue Product Boundary and Testing Conventions

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/frontend_architecture.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../specs/package_quality_standards.spec.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `lib/jido_code_web.ex`
- `lib/jido_code_web/components/`
- `lib/jido_code_web/live/`
- `test/jido_code_web/live/`
- LiveVue component helpers and test helpers

## Relevant Assumptions / Defaults
- Phase 12 has already added the dependency, asset, SSR, and host-shell baseline for `live_vue`.
- The product still needs a consistent boundary so Vue-backed components do not turn into ad hoc client islands with inconsistent event, prop, and test behavior.
- LiveView tests remain the primary routed-surface verification harness, with LiveVue-aware helpers added only where richer components are mounted.

[x] 13 Phase 13 - Live Vue Product Boundary and Testing Conventions
  Standardize how `jido_code` mounts, names, tests, and reasons about Vue-backed components so the richer client layer becomes a product-owned convention rather than a collection of one-off integrations.

  [x] 13.1 Section - Product-Owned Live Vue Mounting Boundary
    Establish shared helpers and conventions so Vue components are mounted through product-approved entrypoints instead of bespoke per-page wiring.

    [x] 13.1.1 Task - Define shared mounting helpers and conventions
      Keep browser composition readable and consistent for contributors as Vue-backed surfaces begin to appear.

      [x] 13.1.1.1 Subtask - Add shared helper or wrapper conventions for mounting LiveVue components from LiveView templates.
      [x] 13.1.1.2 Subtask - Standardize component naming, prop-shape expectations, and event binding patterns for Vue-backed product surfaces.
      [x] 13.1.1.3 Subtask - Preserve server-authored data ownership so Vue components receive bounded product props instead of becoming independent client-side stores.

    [x] 13.1.2 Task - Define event and state handoff rules between LiveView and Vue
      Keep richer interactivity compatible with the product’s existing server-owned state and policy model.

      [x] 13.1.2.1 Subtask - Define how Vue emits map back into LiveView events, actions, or controlled side effects.
      [x] 13.1.2.2 Subtask - Define when ephemeral client-only state is allowed and when state must remain server-authored.
      [x] 13.1.2.3 Subtask - Ensure uploads, stream-driven updates, and typed UI failures still compose through the LiveView-owned shell.

  [x] 13.2 Section - Test Strategy and Contributor Conventions
    Expand the testing model just enough to cover Vue-backed surfaces without abandoning the repo’s strong LiveView-first testing habits.

    [x] 13.2.1 Task - Add LiveVue-aware test helpers and patterns
      Make richer browser surfaces easy to verify without forcing contributors into SPA-style end-to-end testing by default.

      [x] 13.2.1.1 Subtask - Introduce LiveVue-aware test helpers or wrappers for Vue-mounted surfaces.
      [x] 13.2.1.2 Subtask - Keep LiveView tests as the routed-surface default and use LiveVue-specific assertions only where Vue mounting is part of the surface contract.
      [x] 13.2.1.3 Subtask - Preserve stable DOM IDs and selector-driven verification for hybrid LiveView plus Vue screens.

    [x] 13.2.2 Task - Update contributor guidance for the new browser composition model
      Make the adoption path understandable so contributors know when to stay in plain LiveView and when to reach for `live_vue`.

      [x] 13.2.2.1 Subtask - Update AGENTS, README, or contributor guidance with the shared LiveView-plus-LiveVue conventions.
      [x] 13.2.2.2 Subtask - Explain when hooks remain appropriate and when a richer component should instead be implemented through LiveVue.
      [x] 13.2.2.3 Subtask - Keep the new guidance aligned with the package-quality and developer-workflow surfaces.

  [x] 13.3 Section - Phase 13 Integration Tests
    Validate the mounting conventions and test strategy before operator-facing surfaces adopt the new frontend composition model.

    [x] 13.3.1 Task - Mounting and event-bridge scenarios
      Verify shared helpers and event conventions keep LiveView in control while allowing richer Vue-backed components.

      [x] 13.3.1.1 Subtask - Add coverage for shared mounting helpers and bounded prop delivery.
      [x] 13.3.1.2 Subtask - Add coverage for Vue-to-LiveView event handoff and server-authored state refresh behavior.
      [x] 13.3.1.3 Subtask - Add coverage for upload, stream, or typed failure behavior on a representative hybrid surface.

    [x] 13.3.2 Task - Test-harness and contributor-flow scenarios
      Verify contributors can build and verify hybrid surfaces using the intended LiveView-plus-LiveVue workflow.

      [x] 13.3.2.1 Subtask - Add coverage demonstrating the intended LiveVue-aware test path for a mounted component.
      [x] 13.3.2.2 Subtask - Add coverage showing plain LiveView tests remain valid for routes that do not mount Vue.
      [x] 13.3.2.3 Subtask - Verify documentation and planning traceability stay aligned with the new boundary and test conventions.
