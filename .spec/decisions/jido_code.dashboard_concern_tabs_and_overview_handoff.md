---
id: jido_code.dashboard_concern_tabs_and_overview_handoff
status: accepted
date: 2026-04-26
affects:
  - package.jido_code
  - baseline.surface
  - architecture.factory_control_plane
  - architecture.frontend_stack
  - architecture.repo_posture
  - architecture.conversation_orchestration
  - architecture.memory_graph_surface_rollout_and_governance_actions
  - architecture.runtime_service_overlay
---

<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state -->
<!-- covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented -->
<!-- covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented -->
<!-- covers: baseline.surface.welcome_landing_copy -->
<!-- covers: package.jido_code.spec_led_workspace -->

# Dashboard Concern Tabs And Overview Handoff

## Context

`/dashboard` is now the durable authenticated landing route, but it still renders
as one long stacked operator page.

Today that one route cohosts several distinct concern families:

- recent governed runs
- conversation supervision
- repository memory
- runtime posture
- conditional onboarding next actions
- header-level orientation and the settings handoff for provider-login and Git
  automation configuration

That layout is serviceable for early rollout, but it mixes orientation,
follow-up cues, and detailed operator lists into one scan path. Operators have
to traverse multiple unrelated sections even when they only want one concern,
and the route does not yet teach a durable dashboard information architecture.

At the same time, this should not become a route explosion or a client-owned
dashboard application. The existing route already owns authentication, summary
feed loading, and product-language boundaries. The improvement needed here is
clearer concern separation on the same route, not a second browser shell.

## Decision

`Jido.Code` shall keep `/dashboard` as one authenticated LiveView-owned route
while reorganizing its content through route-owned top concern tabs.

The concern model is:

1. `Overview`
   A compact summary-first landing panel that orients the operator with bounded
   counts, posture summaries, and handoffs rather than duplicating every full
   list already shown elsewhere on the route.
2. `Runs`
   The bounded recent governed-runs feed and its existing product-owned run
   links.
3. `Conversations`
   The bounded conversation-supervision roster that routes operators back to
   canonical managed-repository detail instead of becoming a chat inbox.
4. `Memory`
   The bounded repository-memory and workflow-provenance summaries that remain
   action-oriented and product-shaped.
5. `Runtime`
   The bounded runtime-posture and degraded-path summaries that stay expressed
   in product-oriented governance language.
6. `Next Steps`
   A conditional tab shown only when onboarding or ready-state follow-up actions
   are actually present. It does not become permanent empty chrome.

Additional rules:

- the dashboard header, page framing, and settings handoff stay outside the tab
  rail.
- tab selection remains route-owned LiveView state rather than client-only tab
  state.
- richer widgets may continue inside individual dashboard panels, but the route
  shell and concern navigation stay LiveView-owned.
- concern tabs remain bounded projections that hand operators back to canonical
  repo, run, and settings routes rather than becoming separate primary work
  surfaces.

## Consequences

### Positive

- The authenticated landing route gets a durable information architecture
  instead of one growing stack of unrelated sections.
- Operators can scan one concern at a time without losing the dashboard as the
  overview surface.
- Dashboard conversation, memory, and runtime projections stay bounded and
  product-shaped instead of drifting toward inbox, graph-browser, or transport
  console behavior.

### Constraints

- `/dashboard` must remain the routed LiveView host shell.
- `Overview` must summarize and hand off; it should not duplicate the full rows
  from every other concern tab.
- The settings handoff remains part of page framing, not a dashboard concern
  tab.
- Conditional next actions need explicit empty-state behavior so the route does
  not gain dead tab chrome in the normal ready state.

## Implementation Status

This decision is now landed in product code.

Current implementation behaves as follows:

- `/dashboard` remains the durable authenticated LiveView-owned landing route.
- The route now uses route-owned `section` selection to move between
  `Overview`, `Runs`, `Conversations`, `Memory`, `Runtime`, and conditional
  `Next Steps`.
- The concern families remain bounded LiveView-owned slices even though the
  wide-screen chrome has since evolved from a top rail into left-sidebar
  concern navigation.
- `Overview` is still the default authenticated landing concern, but it has
  since evolved from compact summary cards into a repository-first monitoring
  feed under the follow-on dashboard monitoring ADR.
- governed runs, conversation supervision, memory summaries, runtime posture,
  and next steps now render one concern panel at a time instead of one long
  stacked route.
- provider-login and Git automation configuration remain a header-level
  handoff to `/settings/auth`, not a dashboard concern tab.
- browser coverage now exercises the route-owned dashboard concern navigation
  at both wide and narrow viewport sizes on the authenticated landing route.

Current-truth specs should now describe this route-owned concern model directly
rather than framing it as accepted future state.
