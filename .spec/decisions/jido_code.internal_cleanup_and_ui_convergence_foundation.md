---
id: jido_code.internal_cleanup_and_ui_convergence_foundation
status: accepted
date: 2026-04-03
affects:
  - package.jido_code
  - developer.workflow
  - architecture.frontend_stack
  - architecture.factory_control_plane
  - architecture.conversation_driver
  - architecture.runtime_service_overlay
  - architecture.repo_posture
  - architecture.run_governance
  - architecture.policy_layers
  - setup.onboarding
  - docs.product_foundation
---

<!-- covers: package.jido_code.version_controlled_quality_surfaces -->
<!-- covers: developer.workflow.phoenix_mix_surface -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->
<!-- covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context -->
<!-- covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented -->
<!-- covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state -->
<!-- covers: architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress -->
<!-- covers: architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations -->
<!-- covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Internal Cleanup And UI Convergence Foundation

## Context

Phases 1 through 15 established the current control-plane architecture,
runtime-service overlay, and LiveView-plus-LiveVue browser stack. The next
high-value work inside `jido_code` is not another runtime-contract change. It
is reducing internal duplication, tightening the contributor start path around
the current frontend build chain, and making operator-facing warning and
degraded-state presentation more consistent across hybrid and plain LiveView
surfaces.

Before this cleanup:

- owner-authenticated LiveView tests repeated local registration and sign-in
  helpers across many files
- contributor docs still preferred `mix phx.server`, even though the current
  frontend architecture depends on a repo-owned browser toolchain and SSR output
- multiple operator surfaces rendered near-identical typed warning or error
  panels with ad hoc markup

These problems were product-owned internal drift. They made the codebase harder
to maintain without changing the product architecture itself.

## Decision

`jido_code` adopts an internal cleanup and UI-convergence foundation with three
explicit rules:

1. Shared owner-authenticated LiveView test setup shall live in repo-owned
   support helpers rather than repeating equivalent helper code across
   individual routed-surface tests.
2. The canonical local contributor start path shall be repo-owned `mix server`,
   which prepares the current browser dependency or build surface before handing
   off to Phoenix server startup when that preparation is actually needed.
3. Operator-facing typed warning, notice, and error states on migrated surfaces
   shall render through a shared product-owned component so hybrid and plain
   LiveView routes keep one product UI language for degraded or
   refresh-required states.

## Consequences

### Positive

- contributor startup now better matches the current LiveVue and Vite
  architecture
- LiveView test support is easier to maintain and less repetitive
- operator surfaces present more consistent product-authored warning and
  fallback states

### Constraints

- this does not introduce a new frontend stack or runtime contract
- `mix phx.server` may still exist as a lower-level Phoenix task, but repo docs
  and contributor guidance should prefer `mix server`
- shared UI-state extraction must stay product-owned and must not replace
  explicit domain distinctions with generic utility sprawl
