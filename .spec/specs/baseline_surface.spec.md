# Baseline Surface

This subject defines the current browser-facing landing, auth, and routed product surface that operators reach first in `jido_code`.

```spec-meta
id: baseline.surface
kind: feature
status: active
summary: jido_code exposes a welcome landing page and auth entrypoints at the public edge while keeping authenticated product, RPC, API, and dev surfaces declared in the router.
surface:
  - lib/jido_code_web/router.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/components/layouts.ex
  - test/jido_code_web/controllers/page_controller_test.exs
  - test/jido_code_web/live/home_live_test.exs
  - test/jido_code_web/live/welcome_live_test.exs
```

## Requirements

```spec-requirements
- id: baseline.surface.public_entry_routes
  statement: The browser route surface shall keep `/`, `/welcome`, `/setup`, and authentication entrypoints available as the public operator entry surface.
  priority: must
  stability: stable

- id: baseline.surface.product_routes_declared
  statement: Authenticated product routes and deployment integration routes shall remain declared in the router rather than being commented out or silently disabled.
  priority: must
  stability: evolving

- id: baseline.surface.welcome_landing_copy
  statement: The welcome landing page shall present the copy "Welcome to Jido Code" and act as the operator-facing starting point for sign-in and setup.
  priority: must
  stability: stable

- id: baseline.surface.auth_entrypoints_visible
  statement: The landing page shall present local authentication entrypoints for anonymous users, an enabled provider-login entrypoint when configured, and a sign-out control for authenticated users.
  priority: must
  stability: stable

- id: baseline.surface.root_redirects_to_welcome
  statement: The root path shall redirect to `/welcome` so the operator-facing landing route stays canonical even as authenticated product routes expand.
  priority: must
  stability: stable
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
  target: test/jido_code_web/live/welcome_live_test.exs
  covers:
    - baseline.surface.welcome_landing_copy

- kind: command
  target: mix compile
  covers:
    - baseline.surface.public_entry_routes
    - baseline.surface.product_routes_declared
```
