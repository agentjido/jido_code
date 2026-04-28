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
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: package.jido_code.spec_led_workspace -->

# Post-Onboarding Subject Tree Operator Shell

## Context

The current signed-in browser experience improved substantially over the old
stacked pages, but the layout still feels route-by-route instead of product-wide.

Today:

- dashboard uses a left sidebar as the primary concern rail
- managed-repository detail also uses a left sidebar as its primary family rail
- verbose explanatory copy stays visible in navigation chrome instead of only
  when the operator needs orientation
- routes do not yet expose one consistent breadcrumb lane between the page
  header and subject navigation
- information regions inside a selected subject do not yet follow one shared
  header, work, and action layout

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

## Consequences

### Positive

- post-onboarding routes gain one explainable hierarchy instead of several
  similar-but-different navigation patterns
- dashboard, managed-repository detail, and adjacent signed-in surfaces can
  feel more like one coherent desktop workspace
- terse labels reduce chrome noise while the focus bubble keeps explanatory copy
  available when orientation is needed
- breadcrumbs give operators one consistent recovery path back to broader route
  and product context without turning the tab chrome verbose again
- the header, middle, footer structure makes subject panes easier to parse and
  act on quickly

### Constraints

- LiveView remains the routed product host shell
- richer client widgets stay bounded inside the selected subject pane rather
  than becoming owners of shell navigation
- breadcrumbs should remain route-owned orientation chrome instead of becoming
  a second tab system
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

This decision is accepted but not yet landed in product code.

Current implementation still reflects the earlier transitional shell:

- dashboard uses the left sidebar as the primary concern rail
- managed-repository detail uses the left sidebar as the primary family rail
- top-level subject labels still keep more always-visible summary copy than the
  new shell intends
- routes do not yet share one breadcrumb pattern between the page header and
  subject navigation
- selected subject panes do not yet share one explicit header, middle, footer
  contract across the signed-in routes

Current-truth UI specs should now teach the accepted subject-tree shell while
remaining explicit that implementation rollout is still pending.
