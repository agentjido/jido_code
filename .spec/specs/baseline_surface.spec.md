# Baseline Surface

<!-- current_truth.reconciled_with_branch: the signed-in setup start surface remains part of baseline route truth alongside public bootstrap entry behavior, including runtime-default copy that now frames workspace root as seed metadata for new imports, the ready-state local-auth cutover that now defaults to dashboard, a signed-in `/welcome` handoff card that prioritizes dashboard and settings entry over the old stale baseline banner, a settings-owned `/settings/auth` destination as the durable home for provider-login and Git integration management, GitHub PAT encryption preflight plus multi-repository GitHub import selection that clears active selection once import follow-up completes while grouping linked repositories by account origin with the account name visible on each card and leaving repo-level workspace binding as later operator work, `/dashboard` now acting as the durable authenticated landing, `/workbench` remaining a specialist authenticated route rather than the ready-state default, and the post-onboarding subject-tree shell now landing on dashboard and managed-repository detail while product-wide signed-in navigation remains the next follow-on convergence step. -->

This subject defines the current browser-facing landing, auth, and routed product surface that operators reach first in `jido_code`.

<!-- covers: setup.onboarding.post_bootstrap_start_surface -->
<!-- covers: setup.onboarding.runtime_health_transparent_unless_blocking -->

```spec-meta
id: baseline.surface
kind: feature
status: active
summary: jido_code exposes a state-aware `/welcome` landing and auth entry route, keeps `/setup` as the signed-in continuation surface for incomplete onboarding, uses `/dashboard` as the durable ready-state authenticated landing, keeps `/workbench` available only as a specialist authenticated route rather than a peer landing surface, records the landed post-onboarding subject-tree shell for the main signed-in operator routes after onboarding, expects coherent signed-in navigation among the major authenticated routes, and keeps operator auth and Git integration management on `/settings/auth` while authenticated product, API, and dev surfaces remain declared in the router.
decisions:
  - jido_code.dashboard_concern_tabs_and_overview_handoff
  - jido_code.dashboard_developer_centric_monitoring_sidebar
  - jido_code.post_onboarding_subject_tree_operator_shell
  - jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff
surface:
  - .spec/decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md
  - .spec/decisions/jido_code.dashboard_developer_centric_monitoring_sidebar.md
  - .spec/decisions/jido_code.post_onboarding_subject_tree_operator_shell.md
  - .spec/specs/operator_surface_information_architecture.spec.md
  - lib/jido_code_web/router.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/live/setup_live.ex
  - lib/jido_code_web/live_user_auth.ex
  - lib/jido_code_web/plugs/public_bootstrap_auth_gate.ex
  - lib/jido_code_web/components/layouts.ex
  - test/support/conn_case.ex
  - test/jido_code_web/controllers/page_controller_test.exs
  - test/jido_code_web/live/home_live_test.exs
  - test/jido_code_web/live/phase_fifty_eight_integration_test.exs
  - test/jido_code_web/live/phase_fifty_nine_integration_test.exs
  - test/jido_code_web/live/phase_sixty_integration_test.exs
  - test/jido_code_web/live/phase_sixty_three_integration_test.exs
  - test/jido_code_web/live/setup_live_test.exs
  - test/jido_code_web/live/welcome_live_test.exs
```

## Requirements

```spec-requirements
- id: baseline.surface.public_entry_routes
  statement: The browser route surface shall keep `/`, `/welcome`, `/setup`, and authentication entrypoints available, with `/welcome` owning first-run admin bootstrap and public auth entry while `/setup` acts as the signed-in post-bootstrap continuation surface.
  priority: must
  stability: stable

- id: baseline.surface.product_routes_declared
  statement: Authenticated product routes and deployment integration routes shall remain declared in the router rather than being commented out or silently disabled, including the canonical `/repos`, `/repos/:id`, and `/repos/:id/runs/:run_id` operator surfaces.
  priority: must
  stability: evolving

- id: baseline.surface.welcome_landing_copy
  statement: The `/welcome` landing page shall act as the canonical public/bootstrap and auth entry route, keep runtime health checks mostly transparent unless they block bootstrap, and switch between first-run bootstrap copy for zero-user installs, ready-state sign-in copy for signed-out installs, and compact dashboard-plus-settings handoff copy for signed-in ready-state sessions instead of reopening a full operator console.
  priority: must
  stability: stable

- id: baseline.surface.auth_entrypoints_visible
  statement: The landing page shall present the first-admin bootstrap form for zero-user installs, sign-in-only local auth for completed installs, a provider-login entrypoint only after bootstrap is complete and configured, and a sign-out control for authenticated users.
  priority: must
  stability: stable

- id: baseline.surface.root_redirects_to_welcome
  statement: The root path shall redirect to `/welcome` so the canonical public/bootstrap and auth entry route stays canonical even as authenticated product routes expand.
  priority: must
  stability: stable

- id: baseline.surface.welcome_surface_consolidated
  statement: The canonical `/welcome` route shall be implemented by the state-aware home live view rather than a separate legacy welcome live implementation.
  priority: must
  stability: evolving

- id: baseline.surface.dashboard_remains_ready_state_authenticated_landing
  statement: Ready-state authenticated entry shall route operators to `/dashboard`, while `/workbench` may remain a declared specialist authenticated route without displacing dashboard as the default signed-in landing.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code_web/router.ex
  covers:
    - baseline.surface.public_entry_routes
    - baseline.surface.product_routes_declared
    - baseline.surface.root_redirects_to_welcome

- kind: source_file
  target: lib/jido_code_web/live/home_live.ex
  covers:
    - baseline.surface.welcome_landing_copy
    - baseline.surface.auth_entrypoints_visible
    - baseline.surface.welcome_surface_consolidated

- kind: source_file
  target: lib/jido_code_web/live/setup_live.ex
  covers:
    - baseline.surface.public_entry_routes

- kind: source_file
  target: lib/jido_code_web/plugs/public_bootstrap_auth_gate.ex
  covers:
    - baseline.surface.public_entry_routes
    - baseline.surface.auth_entrypoints_visible

- kind: source_file
  target: test/support/conn_case.ex
  covers:
    - baseline.surface.auth_entrypoints_visible

- kind: source_file
  target: test/jido_code_web/controllers/page_controller_test.exs
  covers:
    - baseline.surface.root_redirects_to_welcome

- kind: source_file
  target: test/jido_code_web/live/home_live_test.exs
  covers:
    - baseline.surface.auth_entrypoints_visible
    - baseline.surface.welcome_landing_copy

- kind: source_file
  target: test/jido_code_web/live/phase_fifty_eight_integration_test.exs
  covers:
    - baseline.surface.public_entry_routes
    - baseline.surface.welcome_landing_copy
    - baseline.surface.root_redirects_to_welcome

- kind: source_file
  target: test/jido_code_web/live/phase_fifty_nine_integration_test.exs
  covers:
    - baseline.surface.welcome_landing_copy

- kind: source_file
  target: test/jido_code_web/live/phase_sixty_integration_test.exs
  covers:
    - baseline.surface.public_entry_routes
    - baseline.surface.welcome_landing_copy

- kind: source_file
  target: test/jido_code_web/live/setup_live_test.exs
  covers:
    - baseline.surface.public_entry_routes

- kind: source_file
  target: test/jido_code_web/live/welcome_live_test.exs
  covers:
    - baseline.surface.welcome_landing_copy

- kind: command
  target: test ! -e lib/jido_code_web/live/welcome_live.ex
  covers:
    - baseline.surface.welcome_surface_consolidated

- kind: command
  target: mix compile
  covers:
    - baseline.surface.public_entry_routes
    - baseline.surface.product_routes_declared
    - baseline.surface.dashboard_remains_ready_state_authenticated_landing
```
