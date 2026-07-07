# Phase 100 - Product Surface Rebuild And Legacy UI Deletion

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces -->
<!-- covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands -->
<!-- covers: architecture.frontend_stack.daisyui_removed_from_official_path -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/project_inventory_live.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/live/workflows_live.ex`
- `lib/jido_code_web/live/agents_live.ex`
- `lib/jido_code_web/live/settings_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `lib/jido_code_web/live/work_item_detail_live.ex`
- `lib/jido_code_web/live/evidence_detail_live.ex`
- `lib/jido_code_web/live/decision_detail_live.ex`
- `lib/jido_code_web/live/*.vue`
- `lib/jido_code_web/components/`
- `assets/vue/components/ui/`
- `test/jido_code_web/live/`
- `test/e2e/`

## Relevant Assumptions / Defaults
- The new dependency, CSS, and root area shell foundations from Phases 98 and 99 are available.
- The current UI is not preserved behind compatibility shims; each product surface is rewritten into the new shell and then the old component path is deleted.
- Server-owned forms, actions, auth checks, LiveView streams, product state, and runtime workflows remain authoritative.
- Vue islands use shadcn-vue primitives and explicit semantic-event handoff only where richer client behavior materially helps.
- DaisyUI removal is allowed once all first-party runtime references are gone.

[ ] 100 Phase 100 - Product Surface Rebuild And Legacy UI Deletion
  Rebuild the actual operator product areas inside the new shell and delete the old UI implementation.

  [x] 100.1 Section - Core Area Surface Rebuild
    Recompose the main product areas with SaladUI HEEx primitives and bounded shadcn-vue islands.

    [x] 100.1.1 Task - Rebuild dashboard, repositories, and workbench areas.
      Replace old cards, tabs, and subject-tree content with the new area shell language.

      [x] 100.1.1.1 Subtask - Rebuild dashboard summary, runtime posture, recent work, and next-action panels with `UI.*` HEEx primitives.
      [x] 100.1.1.2 Subtask - Rebuild repository inventory and managed-repository detail panels with server-owned filters, tables, and action buttons.
      [x] 100.1.1.3 Subtask - Rebuild workbench as a dense specialist workspace using the same shell status and handoff contract.

    [x] 100.1.2 Task - Rebuild workflows, agents, and settings areas.
      Make adjacent operational routes feel native to the new shell instead of standalone pages.

      [x] 100.1.2.1 Subtask - Rebuild workflow launch and run history surfaces with SaladUI tables, alerts, and buttons.
      [x] 100.1.2.2 Subtask - Rebuild agents and runtime configuration surfaces with server-owned form and action boundaries.
      [x] 100.1.2.3 Subtask - Rebuild settings, provider auth, GitHub integration, and setup handoff content with the new shell and status patterns.

  [x] 100.2 Section - Detail And Conversation Surface Rebuild
    Bring dense detail routes and conversation surfaces into the same UI reset.

    [x] 100.2.1 Task - Rebuild governed detail surfaces.
      Keep deep operational detail useful while deleting old DaisyUI markup.

      [x] 100.2.1.1 Subtask - Rebuild run detail with SaladUI accordions, tables, badges, alerts, and action buttons.
      [x] 100.2.1.2 Subtask - Rebuild work-item, evidence, and decision detail routes with consistent area context and server-owned actions.
      [x] 100.2.1.3 Subtask - Preserve stable DOM ids needed by existing tests and browser flows where the behavior remains the same.

    [x] 100.2.2 Task - Rebuild conversation and memory surfaces.
      Preserve runtime and recall behavior while replacing visual composition.

      [x] 100.2.2.1 Subtask - Rebuild conversation event streams, composer controls, status badges, cancellation controls, and clarification states using new primitives.
      [x] 100.2.2.2 Subtask - Rebuild memory, provenance, semantic, and source-graph panes with SaladUI server controls and shadcn-vue exploration islands where appropriate.
      [x] 100.2.2.3 Subtask - Keep transcript browsing and semantic graph degradation product-oriented under the new shell.

  [ ] 100.3 Section - Vue Island Rewrite And Legacy Asset Removal
    Replace the current DaisyUI-styled LiveVue widgets with shadcn-vue primitives or delete them.

    [ ] 100.3.1 Task - Rewrite retained Vue islands.
      Make every retained island import only local generated primitives and shared utilities.

      [ ] 100.3.1.1 Subtask - Rewrite retained dashboard, setup, settings, workbench, repository, run, semantic, and memory widgets against `@/vue/components/ui/*`.
      [ ] 100.3.1.2 Subtask - Replace broad component discovery with explicit registry entries and tests for each production island.
      [ ] 100.3.1.3 Subtask - Use explicit semantic-event names and LiveView handlers for all island-to-server actions.

    [ ] 100.3.2 Task - Delete old UI assets and DaisyUI dependencies.
      Remove the old UI implementation after equivalent product paths are rebuilt.

      [ ] 100.3.2.1 Subtask - Delete obsolete Vue widgets, CSS classes, operator-shell helpers, route-local nav fragments, and dead tests.
      [ ] 100.3.2.2 Subtask - Remove DaisyUI from npm dependencies and lockfile after zero first-party class references remain.
      [ ] 100.3.2.3 Subtask - Remove stale docs and comments that describe DaisyUI or the previous subject-tree shell as current truth.

  [ ] 100.4 Section - Integration Tests
    End the phase by proving rebuilt surfaces replace the old UI without losing product behavior.

    [ ] 100.4.1 Task - Add rebuilt surface coverage.
      Verify the main areas and detail routes work through the new shell.

      [ ] 100.4.1.1 Subtask - Add or update LiveView tests for dashboard, repositories, workbench, workflows, agents, settings, and setup handoff.
      [ ] 100.4.1.2 Subtask - Add or update LiveView tests for run, work-item, evidence, decision, conversation, memory, and semantic detail paths.
      [ ] 100.4.1.3 Subtask - Add semantic-event roundtrip tests for every retained LiveVue island.

    [ ] 100.4.2 Task - Add deletion and regression guard coverage.
      Prove the legacy UI no longer exists in the official product path.

      [ ] 100.4.2.1 Subtask - Add a zero-DaisyUI-reference test across first-party `lib`, `assets`, `test`, docs, and planning exceptions.
      [ ] 100.4.2.2 Subtask - Add tests proving old operator navigation modules and old Vue widgets are not imported or mounted.
      [ ] 100.4.2.3 Subtask - Run `mix frontend.verify`, focused LiveView suites, and browser smoke tests for the rebuilt shell.
