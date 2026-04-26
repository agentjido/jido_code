---
id: jido_code.setup_onboarding_live_vue_surface_split
status: accepted
date: 2026-04-23
affects:
  - package.jido_code
  - architecture.frontend_stack
  - setup.onboarding
---

<!-- covers: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions -->
<!-- covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned -->
<!-- covers: setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Setup Onboarding Live Vue Surface Split

## Context

`/setup` is now the signed-in continuation surface after bootstrap, not a
blocking multi-step wizard. That route already mixes several kinds of work:

- route entry, authentication, and persisted onboarding-state hydration
- choice-heavy follow-up UI such as linked GitHub repository scanning
- sensitive setup concerns such as PAT capture, secret-encryption preflight,
  server persistence, and explicit completion into the dashboard

The existing implementation shows that not all of those concerns benefit from
the same browser model. The GitHub repository chooser is a good fit for a
bounded `live_vue` region because it benefits from client-local filtering and a
denser selection layout. The PAT form and completion controls are a poor fit
for being pushed into a larger client-owned shell because they are sensitive,
server-driven, and need a product-owned fallback when richer delivery degrades.

What is missing is a durable rule for how `/setup` should grow if more of the
surface adopts richer interaction, including later layout refinements and
toggle-based multi-repository selection inside the bounded GitHub selector
region, while keeping the repository list authoritative when GitHub-backed
setup validation returns more than the API's default first page of results.

## Decision

`Jido.Code` shall scale `/setup` through bounded `live_vue` regions rather than
through a monolithic Vue rewrite of the full onboarding surface.

The split is:

1. LiveView owns the `/setup` route, auth/session boundary, onboarding-state
   hydration, persistence mutations, flash/navigation, and all server-authored
   gating.
2. Sensitive setup controls remain LiveView-owned, especially GitHub PAT
   capture, encryption-key preflight, secret persistence, and explicit
   completion into the dashboard.
3. Choice-heavy follow-up regions may use bounded `live_vue` widgets when they
   benefit from richer scanning, local filtering, or denser comparison without
   taking route ownership away from LiveView.
4. GitHub repository selection is the reference setup pattern for this split:
   LiveView authors the repository state and import actions, the Vue widget
   renders the richer picker with toggle-based multi-selection, and the route
   carries a server-rendered fallback while completed imports return the picker
   to an unselected state instead of treating import history as active intent.
5. Future setup-facing `live_vue` adoption should prefer additional bounded
   widgets, such as start-path or runtime-default summaries, rather than
   collapsing the whole setup surface into a client-owned application.

## Consequences

### Positive

- `/setup` can gain richer interaction without losing LiveView ownership of the
  entry route.
- Sensitive credential and completion flows stay legible, server-driven, and
  fallback-safe.
- The repo keeps one browser architecture model: LiveView host shell plus
  bounded `live_vue` regions.

### Constraints

- Any new setup-facing Vue widget must cross the product-owned `vue_surface`
  boundary with bounded props and explicit emits.
- Setup mutations should not migrate into client-owned state machines when the
  server already owns the authoritative setup record.
- Richer setup widgets must preserve a server-rendered fallback path when
  `live_vue` delivery is degraded or unavailable.

## Implementation Status

Current setup truth already follows this split:

- PAT capture, encryption preflight, and completion are LiveView-owned.
- GitHub repository selection is the bounded `live_vue` region.
- The route includes a server-rendered fallback selector for that richer
  repository picker.
- Selector-level refinements such as full-width scrolling results and
  non-overlapping control rows remain inside that bounded Vue region rather
  than pulling the surrounding setup shell out of LiveView ownership.
- GitHub-backed repository validation now requests up to 100 repositories per
  page and continues past the first page when needed so the bounded selector
  reflects the full accessible installation or PAT-backed repository set
  instead of truncating at GitHub's default 30-result page.
- That bounded selector now groups repositories by account origin and keeps the
  account name visible on each repository card, with the server-rendered
  fallback mirroring the same grouping model.
