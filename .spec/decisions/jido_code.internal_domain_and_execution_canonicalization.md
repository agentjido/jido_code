---
id: jido_code.internal_domain_and_execution_canonicalization
status: accepted
date: 2026-04-04
affects:
  - architecture.factory_control_plane
  - architecture.run_governance
  - setup.onboarding
  - docs.product_foundation
---

<!-- covers: architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.factory_control_plane.internal_repo_loaders_use_canonical_repo_graph -->
<!-- covers: architecture.run_governance.run_is_preferred_execution_record -->
<!-- covers: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model -->
<!-- covers: architecture.run_governance.greenfield_tests_and_fixtures_create_canonical_run_graph -->
<!-- covers: setup.onboarding.repo_source_per_project -->
<!-- covers: setup.onboarding.greenfield_import_writes_canonical_repo_records -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Internal Domain And Execution Canonicalization

## Context

Phase 17 removed compatibility-era routed surfaces, rollout panels, and mixed-mode
operator vocabulary. The product now presents canonical managed-repository and
governed-run routes externally, but important internal seams still survive:

- repo inventory, setup, and support-agent internals still read or shape older
  `Project` records before canonical managed-repository records
- execution loaders and tests still treat `WorkflowRun` as a convenient internal
  record graph even when governed `Run` already exists
- fixtures and greenfield setup helpers still tend to create previous-era rows
  first and rely on bridge synchronization to reach canonical state

That internal shape is now the main source of accidental regressions. It keeps
old assumptions alive in helpers, tests, and persistence code even though the
product contract no longer supports them.

## Decision

`Jido.Code` shall treat internal repo and execution canonicalization as the next
greenfield cutover step.

The canonical internal model is:

- `SourceRepo` plus `ManagedRepo` for repository identity, scope, setup, and
  operator-facing repo data
- governed `Run`, `ExecutionProfile`, `Evidence`, `ChangeRequest`, and
  `Decision` for execution and review state
- product-owned loaders, fixtures, and setup helpers that create the canonical
  record graph directly instead of relying on older bridge rows

`Project` and `WorkflowRun` may survive temporarily only as low-level,
bounded implementation detail where a current migration, audit trail, or
execution adapter still requires them. They shall no longer be the default
internal read model for operator surfaces, setup helpers, fixtures, or tests.

Greenfield setup and representative tests shall create canonical repo and run
records directly. Internal helpers shall stop mirroring older records forward as
their normal happy path.

## Consequences

- Workbench, setup, support-agent, and related internal loaders should resolve
  repository data from canonical `ManagedRepo` and `SourceRepo` records first.
- Run detail, workbench outcomes, and runtime materialization should resolve
  governed `Run` state first and treat lower-level workflow history as bounded
  internal support data rather than the default record to query.
- Fixtures and setup helpers should stop creating older rows first unless a
  migration-specific or audit-specific test explicitly needs them.
- Remaining `Project` and `WorkflowRun` usage becomes visible technical debt to
  remove, not an accepted long-term internal seam.
