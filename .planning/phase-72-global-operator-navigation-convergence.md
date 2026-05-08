# Phase 72 - Global Operator Navigation Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding -->
<!-- covers: architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers -->
<!-- covers: architecture.operator_surface_information_architecture.desktop_first_operator_shell -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/operator_surface_information_architecture.spec.md`
- `../decisions/jido_code.post_onboarding_subject_tree_operator_shell.md`
- `../planning/phase-68-shared-post-onboarding-operator-shell-foundation.md`
- `../planning/phase-69-dashboard-and-managed-repo-subject-tree-adoption.md`
- `../planning/phase-70-dashboard-work-subject-and-workbench-content-convergence.md`
- `../planning/phase-71-workbench-route-role-and-return-path-convergence.md`
- `lib/jido_code_web/components/layouts.ex`
- `lib/jido_code_web/components/operator_shell_components.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `lib/jido_code_web/live/settings_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `test/e2e/conversation-ui.spec.ts`
- `test/e2e/dashboard-tabs.spec.ts`

## Relevant Assumptions / Defaults
- Phases 68 through 71 have already landed the shared subject-tree shell on the
  main signed-in routes, converged dashboard `Work` with Workbench content, and
  cleaned up route return paths.
- The signed-in product still lacks one easy cross-route navigation model, so
  operators often depend on breadcrumbs, `return_to`, or browser history to
  move across the application.
- Dashboard should remain the durable authenticated home, but Workbench,
  settings, managed-repository detail, and governed-run follow-up still need to
  feel like parts of one product workspace rather than separate route islands.
- The next convergence should stay LiveView-owned, reuse shared route metadata,
  and improve contributor ergonomics by reducing one-off navigation chrome per
  route.

[x] 72 Phase 72 - Global Operator Navigation Convergence
  Add one coherent signed-in navigation layer across the product so operators
  can move easily among major authenticated routes while contributors compose
  that wayfinding through shared LiveView-owned helpers instead of route-local
  duplication.

  [x] 72.1 Section - Global Wayfinding Model And Ownership
    Define what belongs to product-wide navigation versus route-local subject
    navigation before introducing new chrome.

    [x] 72.1.1 Task - Formalize the signed-in major-destination model
      Choose the stable set of major authenticated destinations and the rules
      for how operators should move among them.

      [x] 72.1.1.1 Subtask - Define the durable major destinations such as
        dashboard, settings, specialist inventory mode, managed-repository
        detail, and governed-run follow-up without turning every deep route into
        a peer landing surface.
      [x] 72.1.1.2 Subtask - Keep product-wide wayfinding distinct from the
        subject-tree shell so top-level route movement and route-local subject
        movement do not collapse into one overloaded control.
      [x] 72.1.1.3 Subtask - Preserve contextual breadcrumbs and `return_to`
        paths as orientation aids rather than the only way to navigate.

    [x] 72.1.2 Task - Define contributor-friendly composition seams
      Make the navigation implementation easier to reuse and extend across
      routes.

      [x] 72.1.2.1 Subtask - Standardize shared route metadata or helper shapes
        for product-wide destinations, labels, and contextual entry points.
      [x] 72.1.2.2 Subtask - Keep the navigation LiveView-owned and patchable
        rather than inventing client-only shell memory.
      [x] 72.1.2.3 Subtask - Avoid per-route bespoke top-level nav chrome so
        future signed-in surfaces can compose the same wayfinding model with
        minimal custom code.

  [x] 72.2 Section - Shared Navigation Helpers And Shell Primitives
    Build the reusable product-owned helpers that render the new wayfinding
    layer across authenticated routes.

    [x] 72.2.1 Task - Add shared operator-navigation helpers
      Introduce reusable components or helpers for the major signed-in
      destinations and contextual switchers.

      [x] 72.2.1.1 Subtask - Add shared rendering helpers for major
        destination links, selected-state semantics, and compact route labels.
      [x] 72.2.1.2 Subtask - Add shared hooks for contextual route handoff such
        as recent repos, recent runs, or equivalent product-owned switchers when
        they improve navigation without duplicating route content.
      [x] 72.2.1.3 Subtask - Keep accessibility, focus order, and keyboard
        navigation consistent with the existing operator shell language.

    [x] 72.2.2 Task - Integrate the helpers into the signed-in shell boundary
      Decide where global wayfinding renders relative to route headers,
      breadcrumbs, and subject-tree chrome.

      [x] 72.2.2.1 Subtask - Place the global navigation layer where it stays
        persistent and legible across signed-in routes without competing with
        route-local subject rails.
      [x] 72.2.2.2 Subtask - Preserve desktop-application-like scanability on
        wide screens while keeping narrow-screen fallback bounded and clear.
      [x] 72.2.2.3 Subtask - Ensure settings, Workbench, repo detail, and run
        detail can all adopt the same major-destination chrome without losing
        their route-local identity.

  [x] 72.3 Section - Route Adoption And Navigation Hardening
    Apply the new wayfinding model to the key authenticated routes that still
    feel isolated today.

    [x] 72.3.1 Task - Adopt global wayfinding on adjacent signed-in routes
      Extend the shared navigation layer beyond dashboard and repo detail so the
      signed-in product feels coherent during real working sessions.

      [x] 72.3.1.1 Subtask - Adopt the shared wayfinding model on Workbench and
        settings so both routes clearly rejoin the main signed-in workspace.
      [x] 72.3.1.2 Subtask - Adopt compatible global navigation on managed
        repository detail and governed-run detail so deep follow-up routes do
        not strand operators behind one back link.
      [x] 72.3.1.3 Subtask - Preserve route-local subject-tree navigation and
        pane framing while adding the new cross-route movement layer.

    [x] 72.3.2 Task - Harden route normalization and direct-entry behavior
      Make the new navigation trustworthy even when operators deep-link or
      reload.

      [x] 72.3.2.1 Subtask - Normalize dashboard and adjacent signed-in entry
        routes so global navigation highlights and direct links settle into one
        canonical route state.
      [x] 72.3.2.2 Subtask - Keep direct-entry repo-detail and run-detail
        routes able to recover broader product navigation even when no rich
        parent context is present.
      [x] 72.3.2.3 Subtask - Keep older `return_to` and breadcrumb seams from
        fighting the newer global navigation model.

  [x] 72.4 Section - Phase Integration Tests
    Prove that major signed-in navigation is coherent and contributor-friendly
    across the product rather than only within one route.

    [x] 72.4.1 Task - Add route and browser coverage for global navigation
      Verify that the signed-in wayfinding layer works across major routes and
      deep follow-up surfaces.

      [x] 72.4.1.1 Subtask - Add route coverage proving the major signed-in
        destinations render consistently and preserve selected-state semantics
        across dashboard, Workbench, settings, repo detail, and run detail.
      [x] 72.4.1.2 Subtask - Add browser coverage proving operators can move
        across those routes without relying only on browser back behavior or one
        contextual return link.
      [x] 72.4.1.3 Subtask - Add browser coverage for narrow-screen fallback
        and direct-entry behavior so the new wayfinding remains legible and
        stable under real navigation flows.
