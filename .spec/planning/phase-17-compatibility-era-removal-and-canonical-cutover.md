# Phase 17 - Compatibility Era Removal and Canonical Cutover

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/conversation_driver.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../specs/setup_onboarding.spec.md`
- `../specs/package.spec.md`
- `../specs/product_foundation_docs.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `../decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md`
- `../decisions/jido_code.internal_cleanup_and_ui_convergence_foundation.md`
- `lib/jido_code/`
- `lib/jido_code_web/`
- `priv/repo/migrations/`
- `test/jido_code/`
- `test/jido_code_web/`
- `README.md`
- `CONTRIBUTING.md`

## Relevant Assumptions / Defaults
- Phases 1 through 16 are complete and have landed the current control-plane architecture, runtime-service overlay, LiveView-plus-`live_vue` browser stack, and internal cleanup foundation.
- This repository is treated as greenfield for the next cutover step, so previous-era compatibility code does not need to survive once the specs are updated to the new canonical surfaces.
- The next highest-value work is to remove transition-era shims, routes, labels, projections, and fallback records that still preserve earlier `Project`- and `WorkflowRun`-era compatibility rather than deepening or preserving them.

[ ] 17 Phase 17 - Compatibility Era Removal and Canonical Cutover
  Remove transition-era compatibility code so the product, routes, records, and operator surfaces speak only the current canonical control-plane language and behavior.

  [x] 17.1 Section - Spec And Contract Cutover
    Update the current-truth spec workspace and durable ADR references so the repo no longer claims that older compatibility seams remain part of the intended product shape.

    [x] 17.1.1 Task - Replace transitional architecture language with canonical product contracts
      Remove “transitional,” “compatibility,” and migration-era claims from subjects that have already finished their cutover and make the preferred product objects and routes the only documented truth.

      [x] 17.1.1.1 Subtask - Update the affected subject specs so `ManagedRepo`, governed `Run`, product-owned runtime gateways, and current browser surfaces are described as the only supported product contracts where Phase 17 will remove old seams.
      [x] 17.1.1.2 Subtask - Add or update ADR coverage where removing compatibility behavior changes durable architectural guidance rather than only implementation details.
      [x] 17.1.1.3 Subtask - Remove stale planning, docs, and spec references that still imply prior-era route aliases, fallback records, or compatibility rollout remain required.

    [x] 17.1.2 Task - Define the explicit removal list before implementation
      Make the compatibility removal scope explicit so implementation deletes old seams deliberately rather than opportunistically.

      [x] 17.1.2.1 Subtask - Identify legacy route shapes, compatibility modules, backfill helpers, rollout reports, migration seams, and UI labels that should be deleted rather than preserved.
      [x] 17.1.2.2 Subtask - Identify any remaining persistence or migration helpers that only exist to bridge older `Project` or `WorkflowRun` assumptions into newer control-plane records.
      [x] 17.1.2.3 Subtask - Record which surviving paths are truly canonical and which older entrypoints must be removed rather than redirected.

  [ ] 17.2 Section - Domain, Runtime, And Persistence Seam Removal
    Delete compatibility-era implementation paths so the codebase no longer maintains duplicate domain objects, duplicate execution records, or bridge-only persistence logic for older terminology.

    [ ] 17.2.1 Task - Remove legacy domain and orchestration seams
      Collapse older domain wrappers and execution compatibility paths where the newer control-plane structures are already the current truth.

      [ ] 17.2.1.1 Subtask - Remove compatibility helpers and bridge code that only exist to keep `Project` or `WorkflowRun`-era assumptions alive once their canonical replacements are in place.
      [ ] 17.2.1.2 Subtask - Remove rollout, backfill, or compatibility reporting modules that only serve mixed-mode migration rather than current product behavior.
      [ ] 17.2.1.3 Subtask - Preserve only the canonical product-owned runtime gateways and governed record projections instead of dual execution or projection paths.

    [ ] 17.2.2 Task - Remove migration-era persistence and backfill behavior
      Simplify persistence so the product no longer writes or repairs older compatibility records when the canonical control-plane records already exist.

      [ ] 17.2.2.1 Subtask - Remove code paths that opportunistically backfill, synchronize, or mirror older records purely for compatibility.
      [ ] 17.2.2.2 Subtask - Update migrations, seeds, or data-shaping helpers so greenfield product setup no longer provisions compatibility-era record shapes or assumptions.
      [ ] 17.2.2.3 Subtask - Ensure tests and fixtures create only the canonical record graph required by the current architecture.

  [ ] 17.3 Section - Route, UI, And Contributor Surface Cutover
    Remove compatibility-era user-facing seams so routed product behavior, labels, and contributor guidance only present the current product model.

    [ ] 17.3.1 Task - Replace compatibility routes and labels with canonical product surfaces
      Cut over routed operator and workflow surfaces so old compatibility routes, ids, copy, and fallback labels no longer survive as parallel product vocabulary.

      [ ] 17.3.1.1 Subtask - Remove compatibility route declarations and navigation helpers instead of preserving alias routes once canonical route shapes are defined in specs.
      [ ] 17.3.1.2 Subtask - Update LiveView and LiveVue surfaces so UI labels, headings, DOM ids, and event names reflect only the canonical managed-repo and governed-run model.
      [ ] 17.3.1.3 Subtask - Remove UI messaging that frames canonical behavior as compatibility, migration, or fallback when that language is no longer true.

    [ ] 17.3.2 Task - Align contributor and operator docs to the post-compatibility world
      Make repo-facing documentation describe only the supported current surfaces so new work does not reintroduce removed compatibility seams.

      [ ] 17.3.2.1 Subtask - Update README, CONTRIBUTING, and adjacent repo guides to describe only the canonical route, runtime, and UI surfaces.
      [ ] 17.3.2.2 Subtask - Remove examples, screenshots, or command references that preserve prior-era naming or mixed-mode rollout assumptions.
      [ ] 17.3.2.3 Subtask - Keep test and contributor guidance aligned with the canonical surfaces so future changes do not accidentally recreate compatibility behavior.

  [ ] 17.4 Section - Phase 17 Integration Tests
    Verify that compatibility-era code is actually gone, canonical surfaces remain coherent, and the greenfield product still boots and runs through its current workflows without hidden mixed-mode dependencies.

    [ ] 17.4.1 Task - Canonical surface and removal verification scenarios
      Prove the product no longer depends on compatibility shims in its routed, governed, and contributor-facing behavior.

      [ ] 17.4.1.1 Subtask - Add coverage proving the removed compatibility routes, bridges, or record shims are absent rather than silently still wired.
      [ ] 17.4.1.2 Subtask - Add coverage proving canonical managed-repo, governed-run, and runtime-gateway surfaces continue to work without legacy mirrors.
      [ ] 17.4.1.3 Subtask - Verify docs, specs, and Mix surfaces no longer advertise removed compatibility-era behavior.

    [ ] 17.4.2 Task - Greenfield startup and workflow continuity scenarios
      Prove the repo still behaves correctly for a fresh install without relying on migration-era mixed-mode paths.

      [ ] 17.4.2.1 Subtask - Add coverage for fresh setup, signed-in start, and representative operator flows using only canonical records and routes.
      [ ] 17.4.2.2 Subtask - Add coverage for representative conversation, run, and runtime-evidence flows after compatibility shims are removed.
      [ ] 17.4.2.3 Subtask - Verify cleanup did not reintroduce shadow compatibility helpers, duplicate route shapes, or transitional UI vocabulary.
