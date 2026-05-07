# Phase 68 - Shared Post-Onboarding Operator Shell Foundation

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell -->
<!-- covers: architecture.operator_surface_information_architecture.route_breadcrumbs_sit_between_header_and_subject_navigation -->
<!-- covers: architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/operator_surface_information_architecture.spec.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.post_onboarding_subject_tree_operator_shell.md`
- `lib/jido_code_web/components/layouts.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `test/e2e/dashboard-tabs.spec.ts`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`

## Relevant Assumptions / Defaults
- The accepted subject-tree operator shell is current truth, but the current
  implementation still reflects the earlier sidebar-first dashboard and
  managed-repository detail routes.
- The main LiveView route header remains outside the subject-tree shell and
  continues to own page title, identity, and route-level framing.
- A route-owned breadcrumb lane should sit between that main header and the
  subject-tree navigation so operators can recover context without turning tabs
  into verbose labels.
- The selected child-subject pane, not the whole route, owns the
  `header` / `middle` / `footer` contract.
- Shared shell helpers should remain LiveView-owned and reusable across
  dashboard, managed-repository detail, and adjacent signed-in routes without
  introducing a client-owned shell application.

[x] 68 Phase 68 - Shared Post-Onboarding Operator Shell Foundation
  Establish the shared signed-in operator shell primitives so dashboard,
  managed-repository detail, and adjacent routes can converge on one product
  hierarchy without duplicating shell chrome or inventing client-owned
  navigation state.

  [x] 68.1 Section - Shell Hierarchy And Ownership Contract
    Define the stable shell regions and route-owned state contract before any
    individual route migration tries to fill them with content.

    [x] 68.1.1 Task - Formalize the shell region order and semantics
      Make the route header, breadcrumb lane, parent rail, child rail, and
      selected-pane responsibilities explicit in the implementation boundary.

      [x] 68.1.1.1 Subtask - Keep the route header outside the subject-tree
        shell so title, identity, and route framing do not depend on the
        selected subject.
      [x] 68.1.1.2 Subtask - Add a breadcrumb lane between the route header and
        the subject-tree navigation that reflects route-owned hierarchy without
        becoming a second tab system.
      [x] 68.1.1.3 Subtask - Keep selected-pane `header`, `middle`, and
        `footer` semantics local to the active child subject instead of turning
        them into page-global chrome.

    [x] 68.1.2 Task - Define reusable route-owned subject-tree state
      Establish a common data shape that LiveViews can render directly and patch
      through URLs.

      [x] 68.1.2.1 Subtask - Standardize parent-subject, child-subject,
        breadcrumb, and pane metadata helpers or structs for shared rendering
        boundaries.
      [x] 68.1.2.2 Subtask - Preserve route-owned patchable state for parent and
        child selection instead of introducing client-only shell state.
      [x] 68.1.2.3 Subtask - Keep assistive descriptions and badge or warning
        signals attached to the relevant subject item without duplicating
        verbose explanatory copy across the shell.

  [x] 68.2 Section - Shared LiveView Components And Helpers
    Add reusable shell implementation seams so route migrations do not duplicate
    navigation and pane framing logic.

    [x] 68.2.1 Task - Build shared subject-tree navigation helpers
      Introduce reusable breadcrumb, parent-subject, and child-subject
      components that fit the existing LiveView operator language.

      [x] 68.2.1.1 Subtask - Add shared helpers for breadcrumb rendering,
        top-rail parent subjects, and left-sidebar child subjects with explicit
        selected styling.
      [x] 68.2.1.2 Subtask - Keep focusable description bubbles, `aria-current`
        semantics, and keyboard navigation behavior consistent across routes.
      [x] 68.2.1.3 Subtask - Preserve bounded badge or warning affordances
        without letting shell chrome collapse into summary-card content.

    [x] 68.2.2 Task - Build shared selected-pane framing helpers
      Give adopted routes one consistent pane skeleton for active child
      subjects.

      [x] 68.2.2.1 Subtask - Add pane `header`, `middle`, and `footer` helpers
        or slots that routes can fill with subject-local content.
      [x] 68.2.2.2 Subtask - Keep footer actions square, pane-local, and
        directly tied to the visible middle region.
      [x] 68.2.2.3 Subtask - Keep richer widgets bounded inside the pane body so
        shared shell helpers remain LiveView-owned navigation chrome.

  [x] 68.3 Section - Responsive, Accessibility, And Fallback Convergence
    Preserve the same subject hierarchy under narrower layouts and degraded
    richer-widget delivery.

    [x] 68.3.1 Task - Keep the shell legible across screen sizes and delivery modes
      Ensure the shared shell improves hierarchy without creating a second
      mobile taxonomy or a brittle hybrid boundary.

      [x] 68.3.1.1 Subtask - Compress or restack breadcrumbs, parent subjects,
        and child subjects without changing their meaning or ownership.
      [x] 68.3.1.2 Subtask - Keep screen-reader labels and visual ordering clear
        when the child rail moves above or below the pane on narrow screens.
      [x] 68.3.1.3 Subtask - Preserve LiveView-owned continuity when bounded
        richer widgets degrade, fail, or are absent inside the selected pane.

  [x] 68.4 Section - Phase Integration Tests
    Prove the shared shell contract before route-specific adoption work fans
    out.

    [x] 68.4.1 Task - Add shared-shell route and browser coverage
      Verify the new chrome ordering and pane contract through the first adopted
      surfaces.

      [x] 68.4.1.1 Subtask - Add coverage proving breadcrumbs render between the
        main route header and the subject-tree navigation.
      [x] 68.4.1.2 Subtask - Add coverage proving parent and child selection
        remain route-owned and preserve the same hierarchy in wide and narrow
        layouts.
      [x] 68.4.1.3 Subtask - Add coverage proving the selected pane keeps its
        own `header`, `middle`, and `footer` framing independent of global page
        chrome.
