# Phase 99 - Root Area Shell Routing And Button Menu

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.root_area_shell_owns_navigation -->
<!-- covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../../metagraph/ariston-webui/lib/ariston_webui/areas.ex`
- `../../metagraph/ariston-webui/lib/ariston_webui_web/router.ex`
- `../../metagraph/ariston-webui/lib/ariston_webui_web/components/layouts.ex`
- `../../metagraph/ariston-webui/lib/ariston_webui_web/live/explorer_live.ex`
- `lib/jido_code_web/router.ex`
- `lib/jido_code_web/components/layouts.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/project_inventory_live.ex`
- `lib/jido_code_web/live/settings_live.ex`
- `lib/jido_code_web/operator_navigation.ex`
- `lib/jido_code_web/components/operator_shell_components.ex`
- `test/jido_code_web/live/`
- `test/e2e/`

## Relevant Assumptions / Defaults
- The replacement shell should feel like the ariston area shell: a root LiveView-owned workspace with a top button menu for major product areas.
- Existing authenticated product capabilities remain, but their current route chrome and nested subject-tree composition are discarded.
- Public bootstrap/setup routes may keep a minimal layout until they are intentionally folded into the new shell.
- Detail routes can either be area-owned panels or separate LiveViews that still render inside the new `Layouts.app` shell.
- Navigation state remains server-authored through route params, assigns, and LiveView patch or navigate operations.

[ ] 99 Phase 99 - Root Area Shell Routing And Button Menu
  Replace the current authenticated navigation model with an ariston-style root area shell and button menu.

  [ ] 99.1 Section - Area Model And Route Map
    Define the new product-area taxonomy and connect it to Phoenix routes.

    [ ] 99.1.1 Task - Build the `JidoCodeWeb.Areas` boundary.
      Give the new shell one source of truth for button menu entries, active area state, and handoff targets.

      [ ] 99.1.1.1 Subtask - Add registered areas for the accepted root workspace concerns such as dashboard, repositories, workbench, conversations, workflows, agents, memory, semantic inspection, settings, and setup/admin if applicable.
      [ ] 99.1.1.2 Subtask - Include `area`, `id`, `handoff_id`, `label`, `path`, `local_context_key`, and optional required-auth metadata.
      [ ] 99.1.1.3 Subtask - Provide `shell_state/2`, `navigation_items/0`, `area_metadata!/1`, `area_label/1`, `area_path/1`, and `handoff_targets/1` helpers.

    [ ] 99.1.2 Task - Rework authenticated routes around the area shell.
      Move from many bespoke top-level LiveViews to one coherent shell route map.

      [ ] 99.1.2.1 Subtask - Decide whether one `OperatorRootLive` handles multiple area actions or whether existing LiveViews become thin area modules under the same shell.
      [ ] 99.1.2.2 Subtask - Route `/`, `/dashboard`, `/repos`, `/workbench`, `/workflows`, `/agents`, `/settings`, and selected detail paths through the new shell contract.
      [ ] 99.1.2.3 Subtask - Preserve authenticated and public route gates while removing old global navigation assumptions.

  [ ] 99.2 Section - Layout And Button Menu Replacement
    Replace the current header, global nav, and subject-tree shell with the new external shell.

    [ ] 99.2.1 Task - Rewrite `Layouts.app` for the new shell.
      Make the ariston-style app layout the only authenticated product layout.

      [ ] 99.2.1.1 Subtask - Add title, subtitle, action slot, theme toggle, and area-state assigns.
      [ ] 99.2.1.2 Subtask - Render a top button menu from `JidoCodeWeb.Areas.navigation_items/0` with active state and accessible `aria-current`.
      [ ] 99.2.1.3 Subtask - Render an area status strip for runtime readiness, current repo/work context, warnings, degraded frontend delivery, and operator scope.

    [ ] 99.2.2 Task - Remove old signed-in navigation helpers.
      Delete the previous navigation system once the new shell owns the chrome.

      [ ] 99.2.2.1 Subtask - Remove or rewrite `JidoCodeWeb.OperatorNavigation`.
      [ ] 99.2.2.2 Subtask - Remove or rewrite `OperatorShellComponents` and any subject-tree-only helpers.
      [ ] 99.2.2.3 Subtask - Update all LiveViews to pass `active_area` and `area_state` instead of `operator_navigation`.

  [ ] 99.3 Section - Root Area Content Skeletons
    Introduce simple area panels before rebuilding full product workflows.

    [ ] 99.3.1 Task - Add area-local panel skeletons.
      Keep the shell routable and visible while later phases rebuild dense content.

      [ ] 99.3.1.1 Subtask - Add placeholder-free, product-shaped panels for each major area using SaladUI HEEx primitives.
      [ ] 99.3.1.2 Subtask - Keep area body content in LiveView assigns and product services rather than client-side stores.
      [ ] 99.3.1.3 Subtask - Mount Vue islands only for bounded interactive regions that already have explicit props and event handlers.

    [ ] 99.3.2 Task - Preserve detail-route continuity.
      Keep deep links useful while the root shell replaces the surrounding UI.

      [ ] 99.3.2.1 Subtask - Keep repository, run, work item, evidence, and decision detail routes addressable.
      [ ] 99.3.2.2 Subtask - Render detail routes in the new shell with correct active area and context strip.
      [ ] 99.3.2.3 Subtask - Replace old breadcrumb and context-chip fragments with area handoff targets or shell status content.

  [ ] 99.4 Section - Integration Tests
    End the phase by proving the new shell owns routing, active state, and basic navigation.

    [ ] 99.4.1 Task - Add root shell routing tests.
      Verify every authenticated route enters the same shell language.

      [ ] 99.4.1.1 Subtask - Add LiveView tests for each area route showing the button menu, active button, title, subtitle, and status strip.
      [ ] 99.4.1.2 Subtask - Add tests proving unauthenticated users still land on the expected public/bootstrap flow.
      [ ] 99.4.1.3 Subtask - Add tests proving detail routes keep correct active area and context status.

    [ ] 99.4.2 Task - Add shell browser coverage.
      Verify the button menu and responsive shell work in real browser rendering.

      [ ] 99.4.2.1 Subtask - Add Playwright coverage for desktop and mobile button menu wrapping.
      [ ] 99.4.2.2 Subtask - Add keyboard and accessible-current assertions for area navigation.
      [ ] 99.4.2.3 Subtask - Run `mix frontend.verify` and the focused shell LiveView tests.
