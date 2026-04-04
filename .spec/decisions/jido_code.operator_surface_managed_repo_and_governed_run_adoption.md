---
id: jido_code.operator_surface_managed_repo_and_governed_run_adoption
status: accepted
date: 2026-03-31
affects:
  - architecture.factory_control_plane
  - architecture.repo_posture
  - architecture.conversation_driver
  - setup.onboarding
  - package.jido_code
---

<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state -->
<!-- covers: architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context -->
<!-- covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language -->
<!-- covers: package.jido_code.spec_led_workspace -->

# Operator Surface Managed Repo And Governed Run Adoption

## Context

By Phase 5, `jido_code` already had the preferred control-plane records in place:
`ManagedRepo`, governed `Run`, `Evidence`, `ChangeRequest`, `Decision`, and
`RepoPosture`. The operator-facing browser surfaces, however, still mostly looked
like a `Project` and `WorkflowRun` product with governance data hiding behind
compatibility bridges.

That mismatch made the product harder to understand. The durable records existed,
but the workbench, repo detail, dashboard, and run detail surfaces still taught
operators to think in older transitional terms. At the same time, a hard route
break would be risky while import, backfill, and compatibility cleanup are still
in progress.

## Decision

Operator-facing surfaces shall prefer the control-plane records now, not later.

The workbench and repo-detail path shall resolve repository context through
`ManagedRepo` first and use the canonical `/repos/:id` route as the supported
operator surface. Legacy identifiers may continue to exist internally only where
they are still required to read older records, but they no longer define the
supported browser contract.

Dashboard and run-detail views shall prefer governed `Run` records over direct
`WorkflowRun` assumptions when loading operator-visible run state. Those surfaces
shall expose first-class governance artifacts such as `Evidence`,
`ChangeRequest`, and `Decision` instead of forcing operators to infer review state
from workflow-local maps alone.

This migration cuts the product over to the managed-repo control plane for
operator-facing routes, labels, and primary record loading.

## Consequences

- Operators will see managed-repository and governed-run concepts directly in the
  browser without requiring a route migration first.
- Canonical `/repos` routes become the only supported operator entrypoints.
- Run-detail and dashboard surfaces become explainable governance views instead
  of only workflow audit views.
- Remaining Phase 6 work can harden policy and retire shims from a product surface
  that already reflects the preferred architecture.
