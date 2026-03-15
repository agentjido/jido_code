# Baseline Surface

This subject defines the intentionally reduced application surface used to re-establish a Spec Led Development baseline.

```spec-meta
id: baseline.surface
kind: feature
status: active
summary: jido_code exposes only a welcome landing page and authentication flows while the product surface is temporarily trimmed back.
surface:
  - lib/jido_code_web/router.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/components/layouts.ex
```

## Requirements

```spec-requirements
- id: baseline.surface.routes_landing_and_auth_only
  statement: The browser route surface shall expose only the landing page and authentication flows, including provider-auth handshake endpoints, while baseline mode is active.
  priority: must
  stability: stable

- id: baseline.surface.product_routes_disabled
  statement: Product, setup, RPC, API, and admin route declarations shall remain commented out while baseline mode is active.
  priority: must
  stability: temporary

- id: baseline.surface.welcome_landing_copy
  statement: The landing page shall present the copy "Welcome to Jido Code" and explain that the application has been trimmed to a baseline.
  priority: must
  stability: stable

- id: baseline.surface.auth_entrypoints_visible
  statement: The landing page shall present local authentication entrypoints for anonymous users, an enabled provider-login entrypoint when configured, and a sign-out control for authenticated users.
  priority: must
  stability: stable

- id: baseline.surface.nav_trimmed
  statement: Shared application chrome shall not advertise disabled product areas while baseline mode is active.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code_web/router.ex
  covers:
    - baseline.surface.routes_landing_and_auth_only
    - baseline.surface.product_routes_disabled

- kind: source_file
  target: lib/jido_code_web/live/home_live.ex
  covers:
    - baseline.surface.welcome_landing_copy
    - baseline.surface.auth_entrypoints_visible

- kind: source_file
  target: lib/jido_code_web/components/layouts.ex
  covers:
    - baseline.surface.nav_trimmed

- kind: command
  target: mix compile
  covers:
    - baseline.surface.routes_landing_and_auth_only
```
