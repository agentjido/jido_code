---
id: jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff
status: accepted
date: 2026-04-25
affects:
  - package.jido_code
  - baseline.surface
  - users.admin_system
  - auth.provider_login_flow
  - auth.operator_settings
  - docs.operator_provider_auth_guide
---

# Welcome Bootstrap Entry With Dashboard And Settings Handoff

## Context

`/welcome` currently does too many jobs at once.

It is the canonical public landing route, the first-run bootstrap entrypoint,
the place anonymous users return to for local or provider-backed sign-in, and
today it also becomes the default ready-state landing after authentication.
That same ready-state render still includes the operator-facing Provider Login
and Git Provider Integrations console.

The product surface has moved beyond that early bootstrap shape:

- `/setup` already acts as the signed-in continuation surface while bootstrap or
  onboarding follow-up is still incomplete.
- explicit setup completion already routes the operator into `/dashboard`.
- authenticated operator routes such as dashboard, workbench, repos, run detail,
  and settings are already declared and active.
- `/settings` already exists as the durable operator settings route.

Keeping the ready-state operator auth and integration console on `/welcome`
after every login makes the landing route feel like a permanent admin console
instead of a bootstrap and sign-in entrypoint, and it keeps the default
authenticated handoff behind the product surfaces the operator actually uses.

## Decision

`Jido.Code` shall split bootstrap entry from ready-state product entry.

The split is:

1. `/welcome` remains the canonical public and bootstrap-facing entry route.
   It owns first-run admin bootstrap, public sign-in entry, and state-aware
   handoff into the authenticated product.
2. `/setup` remains the signed-in continuation surface while bootstrap or
   onboarding follow-up is still incomplete.
3. Once bootstrap and onboarding are complete, the default authenticated
   destination should be `/dashboard` rather than returning the operator to a
   full welcome-page console.
4. Provider Login and Git Provider Integrations are durable operator settings,
   not permanent welcome-page content. Their durable home should be a
   settings-owned authenticated surface under `/settings`.
5. The public landing may continue to expose provider sign-in entrypoints when
   bootstrap is complete and provider login is configured, but authenticated
   ready-state sessions should not be returned to a full operator configuration
   console by default.

## Consequences

### Positive

- `/welcome` can stay focused on bootstrap, sign-in, and product handoff.
- Ready-state sign-in will land on a real product overview instead of reopening
  the welcome-page operator console every time.
- Provider-login trust and deployment-local Git automation readiness keep their
  operator boundary, but move toward the existing settings surface where
  operators expect durable configuration controls to live.

### Constraints

- The landing route must still distinguish bootstrap-required,
  continue-setup, and ready states without losing local-auth and
  provider-login entry behavior.
- The auth-settings console must keep the current separation between
  provider-login broker configuration and deployment-local Git service
  credentials when it moves off `/welcome`.
- Redirect behavior for root, local sign-in, and provider sign-in needs an
  explicit cutover rather than an accidental copy change.

## Implementation Status

This decision is accepted, but the full route cutover is not landed yet.

Current implementation still behaves as follows:

- `/` redirects to `/welcome`.
- ready-state local sign-in now defaults to `/dashboard`.
- the Provider Login and Git Provider Integrations console still renders from
  the ready-state home view.

Current-truth specs should therefore keep documenting the existing route
behavior while avoiding language that treats the welcome-page placement of that
operator console as the durable long-term product destination.
