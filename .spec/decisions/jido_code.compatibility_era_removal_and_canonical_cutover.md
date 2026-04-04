---
id: jido_code.compatibility_era_removal_and_canonical_cutover
status: accepted
date: 2026-04-04
affects:
  - architecture.factory_control_plane
  - architecture.conversation_driver
  - architecture.run_governance
  - setup.onboarding
  - docs.product_foundation
---

<!-- covers: architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.factory_control_plane.compatibility_repo_resolution_uses_explicit_control_plane_actors -->
<!-- covers: architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context -->
<!-- covers: architecture.run_governance.run_is_preferred_execution_record -->
<!-- covers: setup.onboarding.repo_source_per_project -->
<!-- covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Compatibility Era Removal And Canonical Cutover

## Context

Earlier migration phases deliberately preserved compatibility-era seams so the
repo could move from `Project` and `WorkflowRun` product concepts toward
`ManagedRepo` and governed `Run` without breaking routed surfaces mid-stream.

That migration work is now complete enough that keeping those seams has become a
liability:

- route aliases still teach older product vocabulary
- setup and scope resolution still carry bridge-only repair logic
- rollout and backfill surfaces keep mixed-mode recovery in the product contract
- contributors can still mistake prior-era records for supported long-term
  product objects

This repository is now treated as greenfield for the next step. The product no
longer needs to preserve prior-era compatibility behavior after the specs are
updated to the canonical surfaces.

## Decision

`Jido.Code` shall cut over to canonical control-plane surfaces and remove the
previous compatibility era from its supported product contract.

The canonical product model is:

- `SourceRepo` as the external repository identity
- `ManagedRepo` as the managed internal repository object
- governed `Run` as the operator-facing execution record
- runtime gateways and conversation boundaries keyed by managed-repo identity

The canonical routed operator surfaces are:

- `/repos`
- `/repos/:id`
- `/repos/:id/runs/:run_id`

Setup and follow-up repository import shall create or update canonical
`SourceRepo` and `ManagedRepo` records directly instead of writing older
`Project` records and mirroring them forward through bridge logic.

Operator-facing workbench, dashboard, repo detail, run detail, workflow launch,
and conversation entry surfaces shall use canonical managed-repo and governed-run
language, identifiers, and navigation. They shall not continue to advertise
mixed-mode route aliases, compatibility rollout health, or legacy identifier
repair as supported product behavior.

Product-owned conversation and runtime entrypoints shall resolve repository scope
through canonical managed-repo reads using explicit actors. They shall not depend
on legacy project identifiers or on-demand compatibility repair to find runtime
context.

Historical or lower-level implementation details may continue to exist
temporarily only if they are strictly internal and no longer define supported
product routes, contributor guidance, or operator-facing truth.

## Consequences

- Compatibility rollout, backfill, and rollback surfaces should be removed from
  current product behavior and documentation.
- Route aliases and UI copy that preserve `Project` or `WorkflowRun` vocabulary
  should be removed instead of maintained.
- Setup, scope resolution, and kickoff paths should stop treating older
  compatibility records as first-class inputs.
- Contributor docs should describe only the canonical repo, run, and runtime
  surfaces.
- Any remaining prior-era records that survive temporarily must become internal
  implementation detail rather than supported product contract.
