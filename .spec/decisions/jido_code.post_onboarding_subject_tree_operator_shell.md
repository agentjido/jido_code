---
id: jido_code.post_onboarding_subject_tree_operator_shell
status: accepted
date: 2026-04-28
affects:
  - package.jido_code
  - baseline.surface
  - architecture.frontend_stack
  - architecture.factory_control_plane
  - setup.onboarding
---

<!-- covers: architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell -->
<!-- covers: architecture.operator_surface_information_architecture.top_level_subject_tabs_use_terse_labels -->
<!-- covers: architecture.operator_surface_information_architecture.subject_tabs_expose_focus_bubble_descriptions -->
<!-- covers: architecture.operator_surface_information_architecture.child_subject_tabs_live_in_left_sidebar -->
<!-- covers: architecture.operator_surface_information_architecture.route_breadcrumbs_sit_between_header_and_subject_navigation -->
<!-- covers: architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions -->
<!-- covers: architecture.operator_surface_information_architecture.desktop_first_operator_shell -->
<!-- covers: architecture.operator_surface_information_architecture.subject_tree_selection_remains_route_owned -->
<!-- covers: architecture.operator_surface_information_architecture.responsive_fallback_preserves_subject_tree_semantics -->
<!-- covers: architecture.operator_surface_information_architecture.dashboard_work_subject_hosts_primary_repo_inventory -->
<!-- covers: architecture.operator_surface_information_architecture.workbench_route_is_specialist_dense_mode -->
<!-- covers: architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding -->
<!-- covers: architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers -->
<!-- covers: architecture.operator_surface_information_architecture.single_concern_routes_reuse_shell_without_fake_subjects -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: package.jido_code.spec_led_workspace -->

# Post-Onboarding Subject Tree Operator Shell

## Context

The current signed-in browser experience improved substantially over the old
stacked pages, but the layout still feels route-by-route instead of product-wide.

Today:

- dashboard and managed-repository detail now share the subject-tree shell
  shape, but the dashboard `Work` subject and `/workbench` still teach slightly
  different repository-inventory mental models
- the densest managed-repository inventory and issue-and-PR triage tooling still
  lives on `/workbench` even though dashboard is now the durable ready-state
  landing route
- repo detail can still fall back toward Workbench context when a route does not
  pass an explicit parent return target
- verbose explanatory copy still needs continued tightening so the newer
  top-level subject chrome stays terse and subject-like across routes
- the signed-in product now has one reusable cross-route navigation model, but
  adjacent routes such as Workbench, repository inventory, workflows, agents,
  settings, and governed-run detail still compose their local pane chrome
  differently enough to feel like separate route islands
- contributors still have to reason about which routes genuinely need a
  subject tree and which should adopt the shared shell proportionately without
  inventing fake local taxonomies

That makes the product harder to scan as a desktop working environment. The UI
needs a stronger subject hierarchy, clearer navigation ownership, and more
consistent work framing after onboarding completes.

The goal is not to introduce a client-owned desktop shell or a separate SPA.
The goal is to keep routed LiveView ownership while converging the signed-in UI
on a clearer, more desktop-application-like subject tree.

## Decision

`Jido.Code` shall organize post-onboarding operator routes through a subject
tree shell.

The shell rules are:

1. Signed-in routes with multiple subject families shall present their first
   subject split as a top rail instead of a primary left-sidebar rail.
2. That first split should reuse the route's canonical top-level subjects, but
   each label should be terse and subject-like, ideally one word.
3. When a terse top-level label needs more explanation, the longer explanation
   shall move into a focusable bubble, tooltip-style affordance, or equivalent
   accessible assistive description instead of remaining permanent verbose tab
   chrome.
4. The selected top-level subject owns the second branch of the tree. Those
   child subjects shall live in the left sidebar for that selected parent.
5. Child subjects shall behave like tabs within the selected parent subject and
   should render as rounded buttons with explicit selected highlighting.
6. A route-owned breadcrumb lane shall appear between the main LiveView page
   header and the subject-tree navigation so operators can recover where the
   current view sits inside the wider product hierarchy.
7. The selected subject pane shall use three durable regions:
   - header: the current subject title plus a short description
   - middle: the information and work surface for that subject
   - footer: square action buttons directly related to the middle region
8. The overall signed-in shell should feel like a desktop application: stable
   panes, persistent hierarchy, and bounded chrome rather than long landing-page
   stacks or generic admin tiles.
9. Navigation state remains route-owned LiveView state even when richer bounded
   widgets render inside the selected subject pane.
10. Responsive fallback may compress or restack the rails, but it must preserve
    the same parent-child subject semantics instead of inventing a separate
    mobile navigation model.
11. Dashboard `Work` owns the primary managed-repository inventory and triage
    model for signed-in operators; tool-named routes such as `/workbench` do
    not become peer top-level subjects in the shared shell.
12. When `/workbench` remains available, it behaves as a denser specialist mode
    or alias for that same repository-inventory domain rather than competing
    with dashboard for ready-state landing or first-level subject ownership.
13. Signed-in routes shall also share a product-wide navigation layer for major
    destinations such as dashboard, settings, specialist inventory mode,
    managed-repository detail, and governed-run follow-up so operators can move
    across the product without depending only on back links or browser history.
14. That product-wide wayfinding should be composed through shared
    LiveView-owned helpers and route metadata rather than each route inventing
    a separate top-level navigation chrome.
15. Routes without multiple real subject families should still reuse the shared
    breadcrumb, pane-framing, and product-wide wayfinding contracts, but they
    should not invent artificial top-rail or child-sidebar subjects simply to
    resemble dashboard or managed-repository detail.

## Consequences

### Positive

- post-onboarding routes gain one explainable hierarchy instead of several
  similar-but-different navigation patterns
- dashboard, managed-repository detail, and adjacent signed-in surfaces can
  feel more like one coherent desktop workspace
- dashboard can absorb the strongest repository-inventory and triage patterns
  from Workbench without teaching operators a second top-level taxonomy
- Workbench can survive as a dense specialist mode or alias without displacing
  the semantic top-level `Work`, `Knowledge`, and `Runtime` structure
- terse labels reduce chrome noise while the focus bubble keeps explanatory copy
  available when orientation is needed
- breadcrumbs give operators one consistent recovery path back to broader route
  and product context without turning the tab chrome verbose again
- the header, middle, footer structure makes subject panes easier to parse and
  act on quickly
- shared cross-route wayfinding makes the signed-in product easier to navigate
  during long developer workflows
- reusable navigation helpers reduce route-by-route shell drift and make future
  signed-in route composition easier for contributors
- proportional shell adoption lets adjacent routes converge on one workspace
  language without forcing fake subject trees onto single-concern surfaces

### Constraints

- LiveView remains the routed product host shell
- richer client widgets stay bounded inside the selected subject pane rather
  than becoming owners of shell navigation
- breadcrumbs should remain route-owned orientation chrome instead of becoming
  a second tab system
- product-wide wayfinding should complement breadcrumbs and return links rather
  than replacing route-local context cues
- child subject trees must remain legible and keyboard-accessible
- subject-footer actions should stay related to the visible middle region
  instead of becoming a global action dump

## Relationship To Earlier Dashboard ADRs

This decision supersedes the shell-level navigation details in both:

- `jido_code.dashboard_concern_tabs_and_overview_handoff`
- `jido_code.dashboard_developer_centric_monitoring_sidebar`

Those ADRs remain useful as historical foundations for moving the product away
from one long dashboard stack. This newer ADR becomes the durable shell-level
rule for post-onboarding routes:

- first-level subjects belong in the top rail
- breadcrumbs belong between the route header and the subject-tree navigation
- second-level subjects belong in the left sidebar under the selected parent
- subject panes use header, middle, and footer structure

Dashboard-specific content rules may still evolve inside that shell, but the
older dashboard-only sidebar shell is no longer the target UI architecture.

## Implementation Status

This decision is partially landed in product code.

Current implementation already reflects the shared shell on dashboard and
managed-repository detail, plus proportional single-pane adoption on the
specialist and inventory routes:

- both routes use the subject-tree ordering of route header, breadcrumb lane,
  top-level subject rail, child-subject sidebar, and selected pane framing
- selected subject panes now follow the shared header, middle, footer contract
- dashboard owns the durable ready-state landing route after onboarding
- `/workbench`, `/repos`, `/workflows`, and `/agents` now reuse the shared
  breadcrumb lane and selected-pane framing without inventing fake subject
  rails

Remaining convergence work is now narrower:

- dashboard `Work` still uses a lighter repository-monitoring view than the
  denser inventory and triage model on `/workbench`
- repo-detail return context still needs cleanup so dashboard-originated flows
  do not implicitly fall back to Workbench semantics
- settings and governed-run detail still render route-specific local bodies
  around the newer shared navigation layer instead of reusing one proportional
  shell contract
- settings still carries bespoke local tab chrome that should either become a
  child-subject rendering inside the shared shell or otherwise align with the
  same route-owned shell primitives

Current-truth UI specs and planning docs should now treat the shared shell as
landed on the main signed-in routes, the global signed-in navigation layer as
landed across the wider product, the proportional shell as landed on the
specialist and inventory routes, and settings plus governed-run shell adoption
as the remaining convergence step.
