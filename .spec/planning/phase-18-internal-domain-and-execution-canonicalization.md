# Phase 18 - Internal Domain and Execution Canonicalization

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/repo_posture.spec.md`
- `../specs/runtime_service_overlay.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/setup_onboarding.spec.md`
- `../specs/package.spec.md`
- `../specs/product_foundation_docs.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `../decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md`
- `../decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md`
- `lib/jido_code/`
- `lib/jido_code_web/`
- `priv/repo/migrations/`
- `test/jido_code/`
- `test/jido_code_web/`
- `README.md`
- `CONTRIBUTING.md`

## Relevant Assumptions / Defaults
- Phases 1 through 17 are complete and have landed the current control-plane architecture, removed compatibility-era routed seams, and established the canonical managed-repo and governed-run product vocabulary.
- This repository is treated as greenfield after the Phase 17 cutover, so internal implementation does not need to preserve `Project`- or `WorkflowRun`-era compatibility once the current-truth spec workspace is updated.
- The next highest-value work is to remove the remaining previous-era internals that still survive behind canonical operator surfaces, especially domain helpers, persistence shims, fixtures, and execution loaders that keep old product records alive as implementation seams.

[x] 18 Phase 18 - Internal Domain and Execution Canonicalization
  Remove the remaining previous-era internal seams so product code, persistence helpers, and tests create and consume only the canonical managed-repo and governed-run model.

  [x] 18.1 Section - Spec And Internal Cutover Contract
    Update the current-truth planning and architecture contract so the codebase no longer treats `Project` and `WorkflowRun` as acceptable long-term implementation seams once this phase lands.

    [x] 18.1.1 Task - Define the canonical internal ownership model
      Clarify which modules, records, and loaders remain canonical after Phase 18 so implementation can delete old seams deliberately instead of only de-emphasizing them.

      [x] 18.1.1.1 Subtask - Update the affected subject specs and ADR references so internal product ownership is described in managed-repo, governed-run, and product-owned gateway terms only.
      [x] 18.1.1.2 Subtask - Record the explicit removal list for `Project`- and `WorkflowRun`-era helpers that survive only as internal translation seams after Phase 17.
      [x] 18.1.1.3 Subtask - Identify any intentionally surviving low-level persistence or migration helpers that must remain only until this phase replaces them with canonical records.

    [x] 18.1.2 Task - Define the greenfield persistence and fixture contract
      Make the expected data-shaping model explicit so setup, tests, and operator flows stop creating old record graphs by habit.

      [x] 18.1.2.1 Subtask - Define which canonical records must exist for fresh setup, operator views, conversations, and governed runs without relying on mirrored legacy rows.
      [x] 18.1.2.2 Subtask - Define fixture and test-helper expectations so new tests create only the canonical record graph needed by the current architecture.
      [x] 18.1.2.3 Subtask - Define which migration or seed behaviors must be simplified so greenfield setup no longer provisions previous-era shapes.

  [x] 18.2 Section - Managed Repo Internal Convergence
    Replace the remaining `Project`-era internals so canonical repo surfaces are backed by managed-repo-first services rather than older domain records and bridge-only helpers.

    [x] 18.2.1 Task - Remove legacy repo-domain implementation seams
      Collapse older repo loaders, bridge helpers, and state shaping paths where managed-repo records are already the supported product truth.

      [x] 18.2.1.1 Subtask - Replace internal loaders and helpers that still fetch or shape `Project` records first when canonical operator surfaces now speak in managed-repo terms.
      [x] 18.2.1.2 Subtask - Remove internal bridge code that mirrors or backfills repo state solely to keep `Project`-era assumptions available behind the scenes.
      [x] 18.2.1.3 Subtask - Preserve only the canonical repo identifiers, loaders, and view-model helpers required by current operator and setup flows.

    [x] 18.2.2 Task - Simplify repo persistence, setup, and fixture behavior
      Ensure fresh setup and tests create the canonical repo graph directly rather than relying on previous-era records and sync behavior.

      [x] 18.2.2.1 Subtask - Update setup and import flows so managed-repo creation is the primary durable path without compatibility mirroring.
      [x] 18.2.2.2 Subtask - Simplify seeds, migrations, and shaping helpers so greenfield installs no longer expect `Project`-era persistence as a prerequisite.
      [x] 18.2.2.3 Subtask - Update test factories, helpers, and fixtures so repo-oriented tests create only canonical repo records and required adjunct state.

  [x] 18.3 Section - Governed Run Internal Convergence
    Replace the remaining `WorkflowRun`-era internals so execution, evidence, and operator run surfaces depend only on governed `Run` behavior and canonical projections.

    [x] 18.3.1 Task - Remove legacy execution-record implementation seams
      Collapse execution loaders, retry paths, and evidence shaping that still depend on `WorkflowRun` as an implementation bridge rather than a canonical governed run.

      [x] 18.3.1.1 Subtask - Replace internal run loaders, live refresh paths, and projection helpers that still read `WorkflowRun` first when governed `Run` is the intended product record.
      [x] 18.3.1.2 Subtask - Remove backfill or mirroring behavior that writes or repairs `WorkflowRun`-era state purely to preserve older execution assumptions.
      [x] 18.3.1.3 Subtask - Preserve only the canonical governed-run lifecycle, evidence, decision, and runtime-evidence projections needed by operator and workflow flows.

    [x] 18.3.2 Task - Simplify run persistence, runtime materialization, and test behavior
      Ensure fresh execution paths and tests materialize governed-run records directly without shadow execution seams.

      [x] 18.3.2.1 Subtask - Update conversation, workflow kickoff, and runtime materialization paths so canonical `Run` records are the only durable execution target.
      [x] 18.3.2.2 Subtask - Update migrations, seeds, and persistence helpers so greenfield installs no longer provision or repair `WorkflowRun`-era record graphs.
      [x] 18.3.2.3 Subtask - Update run-oriented tests and fixtures so they create only canonical governed runs, evidence, and decisions unless a migration-specific test explicitly requires otherwise.

  [x] 18.4 Section - Phase 18 Integration Tests
    Verify that internal canonicalization is complete, fresh setup and operator workflows no longer rely on previous-era records, and cleanup did not reintroduce shadow compatibility seams.

    [x] 18.4.1 Task - Canonical repo and run continuity scenarios
      Prove the product still boots and runs through representative repo, conversation, and governed-run flows using only the canonical internal record graph.

      [x] 18.4.1.1 Subtask - Add coverage for fresh setup and operator flows that create and load canonical managed-repo records without hidden `Project`-era dependencies.
      [x] 18.4.1.2 Subtask - Add coverage for representative execution, retry, conversation, and runtime-evidence flows that materialize governed runs without `WorkflowRun` mirrors.
      [x] 18.4.1.3 Subtask - Verify the current Mix, docs, and contributor surfaces continue to start and exercise the canonical greenfield product successfully.

    [x] 18.4.2 Task - Removal verification scenarios
      Prove the deleted internal seams are absent rather than silently surviving behind canonical operator behavior.

      [x] 18.4.2.1 Subtask - Add coverage proving removed `Project`- and `WorkflowRun`-era helpers, fixtures, or backfill paths are no longer used by current product flows.
      [x] 18.4.2.2 Subtask - Add coverage proving fresh tests and setup helpers create only the canonical record graph required by the current architecture.
      [x] 18.4.2.3 Subtask - Verify cleanup did not leave duplicate route-independent loaders, shadow persistence writers, or previous-era execution vocabulary in product-owned internals.
