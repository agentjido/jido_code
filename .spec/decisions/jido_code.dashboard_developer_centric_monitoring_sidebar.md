---
id: jido_code.dashboard_developer_centric_monitoring_sidebar
status: accepted
date: 2026-04-27
affects:
  - package.jido_code
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
<!-- covers: package.jido_code.spec_led_workspace -->

# Dashboard Developer-Centric Monitoring Sidebar

## Context

The current `/dashboard` implementation improved the old stacked page by adding
route-owned concern tabs, but it is still too concern-first for the actual
operator job.

`Jido.Code` is a software factory. The primary operator task is not to inspect
one concern family in isolation; it is to monitor multiple repositories at once
and quickly see where attention is needed next.

That means the main dashboard should optimize for:

- scanning many repositories as a working set
- identifying which repositories were touched most recently
- spotting urgency without opening each repository route first
- reviewing more repository detail in place without route-hopping
- keeping the route LiveView-owned and product-shaped rather than turning
  dashboard into a client-only workspace shell

The current dashboard concern-tab model is a useful intermediate step, but its
summary-first overview still behaves more like an operator landing page than a
developer-centric monitoring surface.

## Decision

`Jido.Code` shall treat the main authenticated dashboard as a
developer-centric, multi-project monitoring surface.

This refines the earlier dashboard concern-tab decision with the following
rules:

1. `/dashboard` remains one LiveView-owned authenticated route.
2. Dashboard concern navigation moves to a left sidebar that acts as the
   canonical tab rail on wide screens, with a narrower-screen fallback that
   preserves the same route-owned section semantics.
3. `Overview` remains the default dashboard tab, but it becomes
   repository-first rather than summary-first.
4. The `Overview` tab presents repositories ordered by most recent meaningful
   work activity, so the repositories the operator is most likely to care about
   appear first.
5. Each repository in `Overview` renders as a simple monitoring card using the
   same plain bordered card language as the onboarding GitHub repository
   selection, rather than a borderless panel, boxed summary tile grid, or
   generic admin tile.
6. That repository card keeps two stacked zones:
   - the upper summary region focuses on developer monitoring context such as
     repository identity, latest activity, active work signal, and attention
     badges
   - the lower region contains bounded inline detail so the operator can review
     more repository context without leaving the dashboard
7. Inline detail should remain bounded and product-shaped. It may expose
   summaries such as latest governed run state, active conversation state,
   memory or runtime warnings, and direct handoff links back to the canonical
   managed-repository route.
8. The dashboard visual language should favor repository monitoring and working
   context over executive-summary or generic admin-console framing.

The concern families remain useful, but their role changes:

- `Overview` becomes the primary multi-repository monitoring surface.
- other tabs such as runs, conversations, memory, runtime, and conditional next
  steps remain route-owned concern slices available from the left sidebar.
- header framing and the settings handoff remain outside the sidebar/tab body.

### Definition Of "Last Worked On"

For dashboard ordering, "last worked on" should resolve from the most recent
meaningful governed or operator-facing repository activity available to the
product, rather than from static repository metadata alone.

The exact aggregation helper may evolve, but the ordering must stay explainable
to operators and should prefer current productive activity over passive record
age.

## Consequences

### Positive

- The dashboard becomes more aligned with how developers and factory operators
  actually work across many repositories.
- Repositories become the primary scan unit, which matches the control-plane
  model better than a generic top-level summary grid.
- The simple bordered card keeps the dashboard visual language closer to the
  onboarding repository-selection experience while still attaching bounded
  detail directly below the summary.
- Operators can inspect more detail in place before
  deciding whether to jump into repo detail.

### Constraints

- `/dashboard` must remain the routed LiveView host shell.
- The upper repository-summary region and the lower inline-detail region inside
  each monitoring card must stay bounded and monitoring-focused; they should
  not collapse repo detail, workbench, or full transcript surfaces into
  dashboard.
- Inline detail must hand back to canonical repo, run, and settings routes
  rather than becoming a second primary work surface.
- The left sidebar is the canonical wide-screen navigation model, but the route
  still needs a narrow-screen fallback with the same route-owned section
  behavior.

## Relationship To Earlier Dashboard ADR

This decision refines `jido_code.dashboard_concern_tabs_and_overview_handoff`.

The earlier ADR established that dashboard should stay one LiveView-owned route
with explicit concern navigation instead of one long stacked page. That remains
correct.

This newer ADR narrows the next design step:

- concern navigation should become left-sidebar navigation
- `Overview` should become repository-first monitoring
- the dashboard should explicitly optimize for developer/operator monitoring
  across multiple repositories

The broader signed-in shell rule is now superseded by
`jido_code.post_onboarding_subject_tree_operator_shell`, which moves the
first-level subject split back to a top rail and reserves the left sidebar for
child subjects inside the selected parent. The repository-monitoring content
ideas captured here may still inform future `Overview` content inside that
newer shell.

## Implementation Status

Phase 66 landed the left sidebar that acts as the canonical tab rail on wide
screens plus the route-owned narrow-screen fallback.

The repository-first monitoring redesign described by this ADR remains the
accepted target, but the current implementation does not ship that overview
content today. The default `Overview` concern is intentionally empty while the
other routed dashboard concerns remain available, and the dashboard tests now
verify that empty shell rather than repository-monitoring cards or inline
detail.
