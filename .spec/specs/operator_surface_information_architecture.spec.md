# Operator Surface Information Architecture

<!-- current_truth.reconciled_with_branch: post-onboarding UI architecture now records the landed shared subject-tree shell for dashboard and managed-repository detail, keeps a route-owned breadcrumb lane between the main LiveView header and the subject-tree navigation, distinguishes dashboard `Work` as the primary home for managed-repository inventory and triage content, treats `/workbench` as a denser specialist mode rather than a peer top-level subject, and lands product-wide signed-in wayfinding across major routes, while Workbench, repository inventory, workflows, agents, settings, and governed-run detail still use route-local shell bodies that need proportional shared-shell adoption instead of fake subject taxonomies. -->

This subject defines the durable information architecture for signed-in operator
routes after onboarding hands work off to the main product shell.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.operator_surface_information_architecture
kind: policy
status: active
summary: Jido.Code standardizes post-onboarding operator routes on a LiveView-owned subject-tree shell that keeps a route-owned breadcrumb lane between the main header and subject navigation, terse top-level subject tabs in a top rail, route-local child subject tabs as rounded buttons in a left sidebar, accessible focus-bubble descriptions for verbose tab copy, and a desktop-application-like content pane split into header, middle, and footer regions with square footer actions, while preserving route-owned navigation state and responsive fallback semantics across dashboard, managed-repository detail, and adjacent signed-in routes, keeping dashboard `Work` as the primary home for managed-repository inventory and triage content while `/workbench` remains a denser specialist mode or alias instead of becoming a peer top-level subject, and requiring one coherent signed-in navigation layer across product routes so major destinations stay easy to reach.
decisions:
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.live_vue_frontend_adoption
  - jido_code.post_onboarding_subject_tree_operator_shell
surface:
  - .spec/decisions/jido_code.post_onboarding_subject_tree_operator_shell.md
  - .spec/specs/frontend_architecture.spec.md
  - .spec/specs/baseline_surface.spec.md
  - lib/jido_code_web/components/layouts.ex
  - lib/jido_code_web/live/dashboard_live.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code_web/live/workbench_live.ex
  - lib/jido_code_web/live/setup_live.ex
  - test/e2e/dashboard-tabs.spec.ts
  - test/jido_code_web/live/dashboard_live_test.exs
  - test/jido_code_web/live/project_detail_live_test.exs
  - test/jido_code_web/live/workbench_live_test.exs
```

## Requirements

```spec-requirements
- id: architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell
  statement: Post-onboarding operator routes that expose multiple subject families shall converge on one shared subject-tree shell with a top-level subject rail, a route-local child-subject rail, and one selected subject pane rather than each route inventing a separate primary navigation model.
  priority: must
  stability: evolving

- id: architecture.operator_surface_information_architecture.top_level_subject_tabs_use_terse_labels
  statement: The first subject split on a signed-in operator route shall reuse the route's canonical top-level subjects, render them in a top rail, and prefer single-word or otherwise terse subject labels over persistent verbose tab copy.
  priority: must
  stability: evolving

- id: architecture.operator_surface_information_architecture.subject_tabs_expose_focus_bubble_descriptions
  statement: When terse subject labels need explanation, the route shall expose that explanation through a keyboard-focusable bubble, tooltip-style description, or equivalent accessible assistive description rather than keeping multi-line explanatory copy permanently visible in the tab chrome.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.child_subject_tabs_live_in_left_sidebar
  statement: The selected top-level subject shall own its child subjects inside a left sidebar, and those child tabs shall render as rounded buttons with explicit selected highlighting rather than being mixed into the top rail or hidden inside the subject body.
  priority: must
  stability: evolving

- id: architecture.operator_surface_information_architecture.route_breadcrumbs_sit_between_header_and_subject_navigation
  statement: Signed-in operator routes shall expose a route-owned breadcrumb lane between the main LiveView page header and the subject-tree navigation so operators can recover hierarchical context without overloading the tab chrome.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions
  statement: The selected subject pane shall be structured into header, middle, and footer regions where the header describes the current subject, the middle hosts the information and work surface, and the footer presents square action buttons directly related to that middle region.
  priority: must
  stability: evolving

- id: architecture.operator_surface_information_architecture.desktop_first_operator_shell
  statement: Post-onboarding operator routes shall prioritize desktop-application clarity through stable pane hierarchy, persistent subject navigation, and bounded chrome rather than long landing-page stacks, generic admin-card grids, or route-specific one-off navigation patterns.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.subject_tree_selection_remains_route_owned
  statement: Top-level and child-subject selection shall remain route-owned LiveView state even when bounded richer widgets render inside the selected subject pane.
  priority: must
  stability: evolving

- id: architecture.operator_surface_information_architecture.responsive_fallback_preserves_subject_tree_semantics
  statement: Responsive fallback may restack or compress the subject rails, but it shall preserve the same parent-child subject semantics instead of introducing a separate mobile-only navigation model.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.dashboard_work_subject_hosts_primary_repo_inventory
  statement: The dashboard's `Work` subject shall host the primary managed-repository inventory and triage model for signed-in operators rather than promoting `Workbench` to a peer top-level subject in the shared shell.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.workbench_route_is_specialist_dense_mode
  statement: When `/workbench` remains available, it shall act as a denser specialist mode or alias for the same managed-repository inventory and triage content model instead of displacing dashboard as the ready-state landing route or first-level shell taxonomy.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding
  statement: Signed-in operator routes shall expose one coherent product-wide navigation layer for major destinations such as dashboard, settings, specialist inventory modes, managed-repository detail, and governed-run follow-up so operators can move across the application without depending only on browser history, breadcrumbs, or contextual return links.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers
  statement: Product-wide signed-in navigation shall be composed from shared LiveView-owned helpers, metadata, and route contracts rather than each route hand-rolling bespoke top-level wayfinding chrome.
  priority: should
  stability: evolving

- id: architecture.operator_surface_information_architecture.single_concern_routes_reuse_shell_without_fake_subjects
  statement: Signed-in routes that do not expose multiple real subject families should still reuse the shared breadcrumb, pane framing, and global wayfinding contracts, but they shall not invent artificial top-rail or child-sidebar subjects only to mimic multi-concern routes.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: architecture.operator_surface_information_architecture.scenario_route_organizes_subjects_as_tree
  covers:
    - architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell
    - architecture.operator_surface_information_architecture.top_level_subject_tabs_use_terse_labels
    - architecture.operator_surface_information_architecture.child_subject_tabs_live_in_left_sidebar
    - architecture.operator_surface_information_architecture.subject_tree_selection_remains_route_owned
  given:
    - A signed-in operator route such as dashboard or managed-repository detail exposes multiple subject families.
  when:
    - The route renders its shell and the operator selects one top-level subject.
  then:
    - The first split appears in a top rail using terse subject labels.
    - Any child subjects for the selected parent appear in the left sidebar.
    - Selection remains route-authored rather than client-shell-authored state.

- id: architecture.operator_surface_information_architecture.scenario_terse_subject_label_needs_explanation
  covers:
    - architecture.operator_surface_information_architecture.top_level_subject_tabs_use_terse_labels
    - architecture.operator_surface_information_architecture.subject_tabs_expose_focus_bubble_descriptions
  given:
    - A subject label is intentionally terse.
  when:
    - The operator hovers or focuses that label from pointer or keyboard input.
  then:
    - The route reveals the longer explanatory message through a bubble or equivalent accessible assistive description instead of keeping the longer copy permanently visible in the tab row.

- id: architecture.operator_surface_information_architecture.scenario_selected_subject_uses_three_region_pane
  covers:
    - architecture.operator_surface_information_architecture.route_breadcrumbs_sit_between_header_and_subject_navigation
    - architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions
    - architecture.operator_surface_information_architecture.desktop_first_operator_shell
  given:
    - An operator opens one selected subject in the signed-in shell.
  when:
    - The subject pane renders its actual content.
  then:
    - A breadcrumb lane appears between the route header and the subject navigation.
    - The header explains the current subject.
    - The middle hosts the information and work surface.
    - The footer presents square actions related to that middle region.

- id: architecture.operator_surface_information_architecture.scenario_responsive_layout_keeps_same_subject_meaning
  covers:
    - architecture.operator_surface_information_architecture.responsive_fallback_preserves_subject_tree_semantics
    - architecture.operator_surface_information_architecture.child_subject_tabs_live_in_left_sidebar
  given:
    - The route is viewed on a narrower screen.
  when:
    - The shell compresses or restacks its navigation chrome.
  then:
    - The same top-level and child subject structure remains legible.
    - The fallback does not invent a separate subject taxonomy for the narrow layout.

- id: architecture.operator_surface_information_architecture.scenario_dashboard_work_and_workbench_share_inventory_model
  covers:
    - architecture.operator_surface_information_architecture.dashboard_work_subject_hosts_primary_repo_inventory
    - architecture.operator_surface_information_architecture.workbench_route_is_specialist_dense_mode
    - architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell
  given:
    - A signed-in operator needs repository-first scanning or issue-and-PR triage after onboarding.
  when:
    - The operator opens dashboard `Work` and later opens `/workbench` for a denser view of the same domain.
  then:
    - Dashboard `Work` remains the primary subject-level home for managed-repository inventory and triage.
    - `/workbench`, if retained, behaves as a denser specialist mode or alias for that same content model.
    - `Workbench` does not become a peer top-level subject in the shared shell taxonomy.

- id: architecture.operator_surface_information_architecture.scenario_signed_in_operator_moves_across_major_routes
  covers:
    - architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding
    - architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers
    - architecture.operator_surface_information_architecture.desktop_first_operator_shell
  given:
    - An authenticated operator is moving among dashboard, settings, specialist inventory, managed-repository detail, and governed-run follow-up routes during one working session.
  when:
    - The operator needs to switch surfaces without losing orientation or depending on browser back behavior.
  then:
    - The signed-in product exposes a consistent navigation layer for those major destinations.
    - Route-local breadcrumbs and return links remain available, but they are not the only practical way to move around the product.
    - The navigation chrome is built from shared LiveView-owned helpers so contributors do not maintain a separate bespoke top-level navigation pattern on each route.

- id: architecture.operator_surface_information_architecture.scenario_single_concern_route_adopts_proportional_shell
  covers:
    - architecture.operator_surface_information_architecture.single_concern_routes_reuse_shell_without_fake_subjects
    - architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding
    - architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions
  given:
    - A signed-in route such as repository inventory, workflows, agents, or another adjacent operator surface has one primary concern rather than multiple real subject families.
  when:
    - The route adopts the shared signed-in shell language.
  then:
    - The route reuses the shared global wayfinding, breadcrumb lane, and pane framing.
    - The route does not invent artificial parent or child subject rails just to resemble dashboard or managed-repository detail.
    - Any route-local filters, forms, tables, or operator actions remain inside the route's real pane contract.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.post_onboarding_subject_tree_operator_shell.md
  covers:
    - architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell
    - architecture.operator_surface_information_architecture.top_level_subject_tabs_use_terse_labels
    - architecture.operator_surface_information_architecture.subject_tabs_expose_focus_bubble_descriptions
    - architecture.operator_surface_information_architecture.child_subject_tabs_live_in_left_sidebar
    - architecture.operator_surface_information_architecture.route_breadcrumbs_sit_between_header_and_subject_navigation
    - architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions
    - architecture.operator_surface_information_architecture.desktop_first_operator_shell
    - architecture.operator_surface_information_architecture.subject_tree_selection_remains_route_owned
    - architecture.operator_surface_information_architecture.responsive_fallback_preserves_subject_tree_semantics
    - architecture.operator_surface_information_architecture.dashboard_work_subject_hosts_primary_repo_inventory
    - architecture.operator_surface_information_architecture.workbench_route_is_specialist_dense_mode
    - architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding
    - architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers
    - architecture.operator_surface_information_architecture.single_concern_routes_reuse_shell_without_fake_subjects
```
