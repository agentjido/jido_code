# Phase 73 - Adjacent Signed-In Route Shell Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.operator_surface_information_architecture.post_onboarding_routes_share_subject_tree_shell -->
<!-- covers: architecture.operator_surface_information_architecture.subject_content_uses_header_middle_footer_regions -->
<!-- covers: architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding -->
<!-- covers: architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers -->
<!-- covers: architecture.operator_surface_information_architecture.single_concern_routes_reuse_shell_without_fake_subjects -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.adoption_is_incremental_per_surface -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/operator_surface_information_architecture.spec.md`
- `../decisions/jido_code.post_onboarding_subject_tree_operator_shell.md`
- `../planning/phase-68-shared-post-onboarding-operator-shell-foundation.md`
- `../planning/phase-69-dashboard-and-managed-repo-subject-tree-adoption.md`
- `../planning/phase-70-dashboard-work-subject-and-workbench-content-convergence.md`
- `../planning/phase-71-workbench-route-role-and-return-path-convergence.md`
- `../planning/phase-72-global-operator-navigation-convergence.md`
- `lib/jido_code_web/components/layouts.ex`
- `lib/jido_code_web/components/operator_shell_components.ex`
- `lib/jido_code_web/operator_navigation.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/project_inventory_live.ex`
- `lib/jido_code_web/live/workflows_live.ex`
- `lib/jido_code_web/live/agents_live.ex`
- `lib/jido_code_web/live/settings_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `test/e2e/operator-navigation.spec.ts`
- `test/e2e/dashboard-tabs.spec.ts`
- `test/jido_code_web/live/operator_navigation_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`
- `test/jido_code_web/live/project_inventory_live_test.exs`
- `test/jido_code_web/live/workflows_live_test.exs`
- `test/jido_code_web/live/agents_live_test.exs`
- `test/jido_code_web/live/settings_operator_auth_live_test.exs`
- `test/jido_code_web/live/run_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 72 has already landed one shared signed-in navigation layer across the
  major authenticated routes.
- Dashboard and managed-repository detail already use the full subject-tree
  shell and remain the clearest examples of the shared signed-in workspace.
- Workbench, repository inventory, workflows, and agents already reuse the
  proportional shared shell, while settings and governed-run detail are the
  last structural adoption targets in this phase before the final integration
  proof.
- Not every adjacent route should invent top-level subjects or child-sidebar
  tabs; single-concern routes should adopt the shared shell proportionately
  instead of fabricating taxonomy.
- Settings and governed-run detail should keep only the route-local shell depth
  they actually need, but any richer structure must still reuse the same
  LiveView-owned shell primitives rather than bespoke chrome.

[ ] 73 Phase 73 - Adjacent Signed-In Route Shell Adoption
  Converge the remaining signed-in routes on the shared operator-shell language
  so Workbench, repository inventory, workflows, agents, settings, and
  governed-run detail stop reading like isolated pages under the new global
  navigation.

  [x] 73.1 Section - Route Taxonomy And Shared Shell Composition
    Define how adjacent routes should adopt the shared shell without forcing one
    fake navigation pattern onto every route.

    [x] 73.1.1 Task - Classify adjacent routes by shell depth
      Decide which adjacent signed-in routes merit the full subject-tree shell
      and which should keep one real pane with shared outer framing.

      [x] 73.1.1.1 Subtask - Distinguish multi-concern routes that deserve
        parent or child subject navigation from single-concern routes such as
        repository inventory, workflows, or agents that should not invent extra
        taxonomy.
      [x] 73.1.1.2 Subtask - Keep product-wide signed-in navigation outside the
        route-local shell so major-destination movement and route-local pane
        structure remain separate concerns.
      [x] 73.1.1.3 Subtask - Preserve route-owned, patchable state for any real
        local subject selection instead of adding client-only shell memory.

    [x] 73.1.2 Task - Define reusable proportional shell helpers
      Make the adjacent-route adoption path contributor-friendly rather than a
      route-by-route copy-paste exercise.

      [x] 73.1.2.1 Subtask - Standardize a shared breadcrumb plus
        `header` / `middle` / `footer` wrapper for single-pane signed-in
        routes.
      [x] 73.1.2.2 Subtask - Reuse the existing subject-tree helpers on routes
        that genuinely need local multi-concern navigation instead of creating a
        second shell implementation.
      [x] 73.1.2.3 Subtask - Keep richer widgets, filters, tables, and forms
        bounded inside the selected pane contract rather than turning them into
        alternate shell owners.

  [x] 73.2 Section - Specialist And Inventory Route Adoption
    Apply the shared shell language to the adjacent routes that currently feel
    like standalone utility pages.

    [x] 73.2.1 Task - Converge Workbench, Repositories, Workflows, and Agents
      Bring the specialist and inventory routes under one shared shell grammar
      without flattening their real differences in density and workflow.

      [x] 73.2.1.1 Subtask - Reuse the shared breadcrumb lane, route header,
        and pane framing on Workbench, repository inventory, workflows, and
        agents instead of maintaining route-specific top matter.
      [x] 73.2.1.2 Subtask - Keep Workbench explicitly bounded as the dense
        specialist mode while repository inventory, workflow kickoff, and agent
        configuration remain clearly named adjacent product surfaces.
      [x] 73.2.1.3 Subtask - Keep route-local filters, tables, forms, and
        operator actions in the middle and footer regions rather than inventing
        fake subject rails for those single-concern routes.

    [x] 73.2.2 Task - Align route-local actions and wording
      Make the newly aligned routes feel like one signed-in workspace at the
      copy and action-placement level.

      [x] 73.2.2.1 Subtask - Normalize where adjacent routes place their
        primary actions so pane-local actions consistently live in shell-owned
        header or footer regions.
      [x] 73.2.2.2 Subtask - Align role labels, route descriptions, and return
        cues with the newer dashboard-first signed-in workspace model.
      [x] 73.2.2.3 Subtask - Retire duplicated route-local breadcrumb or
        top-level navigation fragments once the shared shell fully owns them.

  [x] 73.3 Section - Settings And Governed-Run Shell Adoption
    Bring the more structurally complex adjacent routes into the same shell
    model without erasing their real local concerns.

    [x] 73.3.1 Task - Converge settings local navigation
      Decide whether the current settings tab model should become child-subject
      navigation or another equivalent shared-shell rendering.

      [x] 73.3.1.1 Subtask - Convert settings navigation to shared shell
        primitives so GitHub, agents, account, auth, and security concerns no
        longer live behind bespoke route-local chrome.
      [x] 73.3.1.2 Subtask - Keep the bounded settings overview widget and the
        server-owned forms or modals inside the selected pane regions rather
        than outside the shell contract.
      [x] 73.3.1.3 Subtask - Preserve patchable tab routing and settings-owned
        auth/integration semantics while aligning the visual shell with the rest
        of the signed-in workspace.

    [x] 73.3.2 Task - Converge governed-run detail framing
      Make governed-run detail feel like a true follow-up route inside the same
      signed-in workspace rather than a standalone deep-link page.

      [x] 73.3.2.1 Subtask - Reuse the shared breadcrumb, header, and pane
        framing on run detail so it visually aligns with the adjacent product
        routes that hand off into it.
      [x] 73.3.2.2 Subtask - Preserve repository parent context, governed
        follow-up links, and route-owned continuity inside the shared shell
        rather than pushing that context back into ad hoc local chrome.
      [x] 73.3.2.3 Subtask - Avoid inventing fake local taxonomies if
        governed-run detail still behaves as one primary concern with bounded
        subsections instead of a full multi-subject route.

  [x] 73.4 Section - Phase Integration Tests
    Prove that adjacent signed-in routes now read like one workspace rather than
    a collection of unrelated authenticated pages.

    [x] 73.4.1 Task - Add route and browser coverage for adjacent shell adoption
      Verify the shared shell at the same fidelity as the earlier shell and
      navigation phases.

      [x] 73.4.1.1 Subtask - Add route coverage proving Workbench,
        repository inventory, workflows, agents, settings, and governed-run
        detail all render the shared global navigation plus proportional shell
        framing consistently.
      [x] 73.4.1.2 Subtask - Add coverage proving routes that keep one primary
        pane do not invent fake subject rails, while routes with real local
        concerns preserve patchable route-owned selection.
      [x] 73.4.1.3 Subtask - Add browser coverage proving wide and narrow
        layouts remain legible across those adjacent routes without regressing
        breadcrumb context, parent-surface continuity, or route-local actions.
