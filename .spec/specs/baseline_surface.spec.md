# Baseline Surface

<!-- current_truth.reconciled_with_branch: the signed-in setup start surface remains part of baseline route truth alongside public bootstrap entry behavior, including GitHub PAT encryption preflight before secret-backed follow-up actions and multi-repository GitHub import selection after bootstrap. -->

This subject defines the current browser-facing landing, auth, and routed product surface that operators reach first in `jido_code`.

<!-- covers: setup.onboarding.post_bootstrap_start_surface -->
<!-- covers: setup.onboarding.runtime_health_transparent_unless_blocking -->

```spec-meta
id: baseline.surface
kind: feature
status: active
summary: jido_code exposes a state-aware `/welcome` landing page and public auth entrypoints while keeping authenticated product, API, and dev surfaces declared in the router.
surface:
  - lib/jido_code_web/router.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/live/setup_live.ex
  - lib/jido_code_web/plugs/public_bootstrap_auth_gate.ex
  - lib/jido_code_web/components/layouts.ex
  - test/support/conn_case.ex
  - test/jido_code_web/controllers/page_controller_test.exs
  - test/jido_code_web/live/home_live_test.exs
  - test/jido_code_web/live/setup_live_test.exs
  - test/jido_code_web/live/welcome_live_test.exs
```

## Requirements

```spec-requirements
- id: baseline.surface.public_entry_routes
  statement: The browser route surface shall keep `/`, `/welcome`, `/setup`, and authentication entrypoints available, with `/welcome` owning first-run admin bootstrap and `/setup` acting as the signed-in post-bootstrap start surface.
  priority: must
  stability: stable

- id: baseline.surface.product_routes_declared
  statement: Authenticated product routes and deployment integration routes shall remain declared in the router rather than being commented out or silently disabled, including the canonical `/repos`, `/repos/:id`, and `/repos/:id/runs/:run_id` operator surfaces.
  priority: must
  stability: evolving

- id: baseline.surface.welcome_landing_copy
  statement: The `/welcome` landing page shall act as the operator-facing starting point, keep runtime health checks mostly transparent unless they block bootstrap, and switch between first-run bootstrap copy for zero-user installs and ready-state sign-in copy once bootstrap is complete.
  priority: must
  stability: stable

- id: baseline.surface.auth_entrypoints_visible
  statement: The landing page shall present the first-admin bootstrap form for zero-user installs, sign-in-only local auth for completed installs, a provider-login entrypoint only after bootstrap is complete and configured, and a sign-out control for authenticated users.
  priority: must
  stability: stable

- id: baseline.surface.root_redirects_to_welcome
  statement: The root path shall redirect to `/welcome` so the operator-facing landing route stays canonical even as authenticated product routes expand.
  priority: must
  stability: stable

- id: baseline.surface.welcome_surface_consolidated
  statement: The canonical `/welcome` route shall be implemented by the state-aware home live view rather than a separate legacy welcome live implementation.
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
```
