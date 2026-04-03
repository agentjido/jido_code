# Phase 16 - Internal Cleanup and UI Convergence Foundation

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../specs/developer_workflow.spec.md`
- `../specs/package_quality_standards.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `mix.exs`
- `README.md`
- `CONTRIBUTING.md`
- `lib/jido_code/`
- `lib/jido_code_web/`
- `test/jido_code/`
- `test/jido_code_web/`

## Relevant Assumptions / Defaults
- Phases 1 through 15 are complete and have landed the current control-plane architecture, runtime-service overlay boundary, and the LiveView-plus-`live_vue` browser stack.
- `jido_os` is currently under review, so this phase should avoid changing product assumptions about upstream runtime internals or introducing new boundary contracts.
- The next highest-value work is inside `jido_code` itself: reducing duplicated helpers and transitional seams, tightening startup and command behavior around the current frontend architecture, and making operator-facing UI behavior more consistent.

[x] 16 Phase 16 - Internal Cleanup and UI Convergence Foundation
  Consolidate `jido_code`’s own implementation seams so the product’s internal boundaries, startup behavior, and operator UI patterns become easier to maintain without depending on further upstream runtime changes.

  [x] 16.1 Section - Internal Boundary and Helper Cleanup
    Reduce duplicated product-side shaping and transitional glue so internal architecture is clearer before the next wave of feature work.

    [x] 16.1.1 Task - Extract and standardize shared product helpers
      Centralize repeated product-owned logic that is currently copied across LiveViews, bridges, and tests into clearer shared helpers.

      [x] 16.1.1.1 Subtask - Identify repeated auth, actor, repo, view-model, or runtime-posture helper logic across `lib/` and `test/`.
      [x] 16.1.1.2 Subtask - Extract shared helpers only where the shared boundary improves product clarity rather than hiding important domain distinctions.
      [x] 16.1.1.3 Subtask - Preserve explicit control-plane ownership and avoid pushing product decisions down into generic utility modules.

    [x] 16.1.2 Task - Retire or shrink transitional implementation seams
      Simplify code paths that still reflect earlier migration stages when the newer control-plane or frontend structure is already the current truth.

      [x] 16.1.2.1 Subtask - Identify legacy or migration-era shaping that remains only for historical reasons rather than current product behavior.
      [x] 16.1.2.2 Subtask - Collapse obsolete indirection where newer product-owned records, gateways, or shared frontend boundaries have already replaced it.
      [x] 16.1.2.3 Subtask - Keep compatibility only where an active user-facing or operator-facing path still depends on it.

  [x] 16.2 Section - Startup, Mix Surface, and UI State Convergence
    Make the application start path and operator-facing UI states reflect the current architecture consistently instead of depending on scattered per-surface conventions.

    [x] 16.2.1 Task - Align application start and build entrypoints with the current frontend architecture
      Ensure the Mix and startup paths that contributors actually use consistently respect the LiveView-plus-`live_vue` browser stack and its build chain.

      [x] 16.2.1.1 Subtask - Audit `mix` aliases and app-start entrypoints that developers use to boot Phoenix or related product processes.
      [x] 16.2.1.2 Subtask - Make the relevant start-oriented command surface trigger or require the correct frontend build chain where appropriate.
      [x] 16.2.1.3 Subtask - Keep the fast local loop understandable and avoid introducing hidden startup work that makes normal Phoenix development surprising.

    [x] 16.2.2 Task - Standardize operator-facing UI states across migrated surfaces
      Make hybrid and plain LiveView surfaces present loading, empty, warning, fallback, and refresh states with a more consistent product narrative.

      [x] 16.2.2.1 Subtask - Audit dashboard, workbench, project detail, run detail, settings, and related operator surfaces for repeated or inconsistent UI states.
      [x] 16.2.2.2 Subtask - Extract or standardize shared operator-state presentation where consistency improves comprehension and maintenance.
      [x] 16.2.2.3 Subtask - Preserve LiveView ownership and bounded Vue regions while avoiding a second per-page UI language for the same product concepts.

  [x] 16.3 Section - Phase 16 Integration Tests
    Validate that the cleanup work improves maintainability and consistency without regressing startup behavior, product boundaries, or operator workflows.

    [x] 16.3.1 Task - Internal cleanup and startup convergence scenarios
      Verify that shared helper extraction and start-path cleanup preserve the product’s current control-plane and frontend behavior.

      [x] 16.3.1.1 Subtask - Add coverage for the updated start-oriented Mix or app entrypoints where frontend build-chain expectations changed.
      [x] 16.3.1.2 Subtask - Add coverage for any extracted shared product helpers that now own repeated shaping or boundary logic.
      [x] 16.3.1.3 Subtask - Verify planning, specs, and contributor-facing command surfaces remain aligned after the cleanup.

    [x] 16.3.2 Task - Operator UI consistency scenarios
      Verify the migrated operator surfaces still behave correctly while presenting more uniform product-owned UI states.

      [x] 16.3.2.1 Subtask - Add coverage for standardized loading, empty, warning, fallback, or refresh behavior on representative operator surfaces.
      [x] 16.3.2.2 Subtask - Add coverage showing hybrid LiveView-plus-Vue surfaces and plain LiveView surfaces remain coherent under the same product-state conventions.
      [x] 16.3.2.3 Subtask - Verify cleanup did not reintroduce runtime-topology leakage, ad hoc client islands, or legacy migration-state language into the UI.
