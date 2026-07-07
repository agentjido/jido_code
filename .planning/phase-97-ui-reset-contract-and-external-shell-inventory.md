# Phase 97 - UI Reset Contract And External Shell Inventory

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.frontend_stack.liveview_remains_product_host_shell -->
<!-- covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces -->
<!-- covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../../metagraph/ariston-webui/lib/ariston_webui/areas.ex`
- `../../metagraph/ariston-webui/lib/ariston_webui_web/router.ex`
- `../../metagraph/ariston-webui/lib/ariston_webui_web/components/layouts.ex`
- `../../metagraph/ariston-webui/lib/ariston_webui_web/components/ui.ex`
- `../../metagraph/ariston-webui/components.json`
- `../../metagraph/ariston-webui/assets/vue/components/ui/`
- `lib/jido_code_web/router.ex`
- `lib/jido_code_web/components/layouts.ex`
- `lib/jido_code_web/components/core_components.ex`
- `lib/jido_code_web/components/live_vue_components.ex`
- `lib/jido_code_web/live/`
- `assets/css/app.css`
- `assets/vue/`
- `package.json`
- `mix.exs`

## Relevant Assumptions / Defaults
- This is a greenfield UI reset, not an incremental compatibility rollout.
- Product data, auth, runtime, conversation, semantic, memory, and governed-work services remain authoritative server-side boundaries.
- The ariston-webui shell is the local implementation reference for route-area navigation, the root LiveView shell, SaladUI-backed HEEx primitives, and generated shadcn-vue assets.
- The current subject-tree/operator-shell UI, DaisyUI classes, and existing Vue widgets are deletion or rewrite targets unless explicitly retained behind the new shell contract.
- `shadcdn` in project shorthand means the shadcn-vue generated component path under `assets/vue/components/ui`, backed by local assets and normal npm dependencies.

[ ] 97 Phase 97 - UI Reset Contract And External Shell Inventory
  Define the replacement target and deletion boundary before any UI code is moved so the reset stays deliberate, complete, and testable.

  [x] 97.1 Section - Target Shell Contract
    Describe the future shell as one LiveView-owned product application with bounded Vue islands and no legacy UI compatibility layer.

    [x] 97.1.1 Task - Define the root LiveView and area-routing model.
      Establish the ariston-style root shell semantics for `jido_code` before replacing current routes.

      [x] 97.1.1.1 Subtask - Define a `JidoCodeWeb.Areas` or equivalent module with registered product areas, ids, labels, paths, local context keys, and handoff targets.
      [x] 97.1.1.2 Subtask - Decide which routes become root-shell areas versus route-specific detail views under the same shell.
      [x] 97.1.1.3 Subtask - Specify that area selection is route-owned and patchable or navigable through LiveView, not browser-local menu state.

    [x] 97.1.2 Task - Define the external shell replacement boundary.
      Make the ariston-style header, status strip, and button menu the new product chrome.

      [x] 97.1.2.1 Subtask - Map the ariston layout regions to `jido_code`: brand block, route subtitle, action slot, theme toggle, area button menu, status strip, and content body.
      [x] 97.1.2.2 Subtask - Define how authenticated scope, runtime readiness, warnings, and repo context appear in the shell status strip.
      [x] 97.1.2.3 Subtask - Declare the previous subject-tree shell, dashboard concern tabs, and bespoke signed-in navigation helpers as replacement targets.

  [ ] 97.2 Section - Current UI Deletion Inventory
    Inventory every current UI file and CSS dependency that must be replaced so DaisyUI and legacy shell assumptions do not survive by accident.

    [ ] 97.2.1 Task - Inventory LiveView and HEEx UI surfaces.
      Identify the server-rendered surfaces that need either full deletion or rewrite under the new shell.

      [ ] 97.2.1.1 Subtask - Classify each `lib/jido_code_web/live/*_live.ex` route as root area, detail route, setup/public route, or deletion target.
      [ ] 97.2.1.2 Subtask - Classify `components/layouts.ex`, `operator_shell_components.ex`, `operator_state_components.ex`, `managed_repo_inventory_components.ex`, conversation components, memory components, and core components as keep, rewrite, or delete.
      [ ] 97.2.1.3 Subtask - Record stable product behaviors that must survive even when their current UI markup is discarded.

    [ ] 97.2.2 Task - Inventory Vue widgets and browser assets.
      Decide which current LiveVue components should be rewritten against shadcn-vue primitives and which should be removed.

      [ ] 97.2.2.1 Subtask - Classify every `lib/jido_code_web/live/*.vue` component as retained island, rewritten island, or deletion target.
      [ ] 97.2.2.2 Subtask - Identify all DaisyUI class usage in Vue, HEEx, CSS, tests, and helpers.
      [ ] 97.2.2.3 Subtask - Identify asset entrypoints, Vite config, SSR entrypoints, and test helpers that need to adopt the explicit island registry pattern from ariston-webui.

  [ ] 97.3 Section - Deletion Policy And Migration Order
    Set the greenfield rule that old UI is removed once the replacement path exists instead of retaining mixed shells.

    [ ] 97.3.1 Task - Define no-compatibility UI reset rules.
      Prevent the reset from becoming a second long-lived UI architecture.

      [ ] 97.3.1.1 Subtask - State that there will be no DaisyUI compatibility layer after the cutover phase.
      [ ] 97.3.1.2 Subtask - State that old route chrome, old operator-navigation helpers, and old Vue widgets are deleted or rewritten rather than hidden.
      [ ] 97.3.1.3 Subtask - Keep only product service contracts, test fixtures, auth/session behavior, and LiveVue mount helpers where they still fit the new shell.

    [ ] 97.3.2 Task - Sequence the reset around safe compile boundaries.
      Keep the repo buildable while still planning for complete UI replacement.

      [ ] 97.3.2.1 Subtask - Do dependency and CSS foundation work before route deletion.
      [ ] 97.3.2.2 Subtask - Land the root area shell before rewriting product area content.
      [ ] 97.3.2.3 Subtask - Remove DaisyUI only after every runtime reference to DaisyUI component classes is gone.

  [ ] 97.4 Section - Integration Tests
    End the phase with planning-level contract tests that make the UI reset scope visible before implementation begins.

    [ ] 97.4.1 Task - Add inventory and contract guard coverage.
      Verify the reset plan is represented by executable checks before code replacement starts.

      [ ] 97.4.1.1 Subtask - Add a frontend reset contract test that lists the expected new shell boundary files and deletion targets.
      [ ] 97.4.1.2 Subtask - Add a current DaisyUI usage inventory assertion that can be driven to zero in later phases.
      [ ] 97.4.1.3 Subtask - Add a route inventory assertion that distinguishes root-shell area routes from detail routes and public setup routes.

    [ ] 97.4.2 Task - Verify planning traceability.
      Prove the UI reset track is discoverable and consistent with repo planning conventions.

      [ ] 97.4.2.1 Subtask - Update `.planning/README.md` with the Phase 97 through Phase 101 reset track.
      [ ] 97.4.2.2 Subtask - Add developer guidance references for the ariston-style shell, SaladUI, and shadcn-vue asset split.
      [ ] 97.4.2.3 Subtask - Run focused documentation or planning checks used by the repo for phase traceability.
