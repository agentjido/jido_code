# Phase 98 - SaladUI And Shadcn-Vue Foundation

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands -->
<!-- covers: architecture.frontend_stack.daisyui_removed_from_official_path -->
<!-- covers: architecture.frontend_stack.product_owned_mounting_boundary -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../../metagraph/ariston-webui/mix.exs`
- `../../metagraph/ariston-webui/package.json`
- `../../metagraph/ariston-webui/components.json`
- `../../metagraph/ariston-webui/assets/css/app.css`
- `../../metagraph/ariston-webui/assets/js/app.js`
- `../../metagraph/ariston-webui/assets/vue/components/ui/`
- `../../metagraph/ariston-webui/lib/ariston_webui_web/components/ui.ex`
- `mix.exs`
- `package.json`
- `package-lock.json`
- `assets/css/app.css`
- `assets/js/app.js`
- `assets/vue/`
- `lib/jido_code_web/components/core_components.ex`
- `lib/jido_code_web/components/live_vue_components.ex`
- `lib/jido_code_web.ex`

## Relevant Assumptions / Defaults
- SaladUI is the HEEx/LiveView primitive source for richer server-rendered controls.
- shadcn-vue primitives are generated into the repo under `assets/vue/components/ui` and imported by Vue islands; the generated primitives are not LiveVue mount targets.
- Phoenix core components remain appropriate for server-owned forms, icons, flashes, and simple inputs unless replaced intentionally.
- Shared CSS tokens must support both SaladUI-generated HEEx markup and shadcn-vue generated assets without DaisyUI themes.
- `mix frontend.verify` remains the browser-pipeline verification gate for dependency, Vite, SSR, and shared browser-helper changes.

[ ] 98 Phase 98 - SaladUI And Shadcn-Vue Foundation
  Replace the current DaisyUI browser foundation with the ariston-style SaladUI plus generated shadcn-vue primitive stack.

  [x] 98.1 Section - Dependency And Asset Baseline
    Add the server and browser dependencies needed by the new UI foundation while keeping setup Mix-first.

    [x] 98.1.1 Task - Add SaladUI to the Elixir dependency surface.
      Make SaladUI an explicit product dependency for LiveView-side UI primitives.

      [x] 98.1.1.1 Subtask - Add `{:salad_ui, "~> 1.0.0-beta.3"}` or the currently accepted compatible version to `mix.exs`.
      [x] 98.1.1.2 Subtask - Start `TwMerge.Cache` under application supervision if SaladUI requires it.
      [x] 98.1.1.3 Subtask - Add a `JidoCodeWeb.Components.UI` boundary that delegates only the selected SaladUI primitives.

    [x] 98.1.2 Task - Add shadcn-vue asset dependencies.
      Make generated Vue primitives available to LiveVue islands through local assets.

      [x] 98.1.2.1 Subtask - Add `components.json` configured for `assets/css/app.css`, `@/vue/components`, `@/vue/components/ui`, `@/vue/lib`, and `@/vue/composables`.
      [x] 98.1.2.2 Subtask - Add npm dependencies for the generated primitives, including `reka-ui`, `class-variance-authority`, `clsx`, `tailwind-merge`, `tw-animate-css`, and icon packages as needed.
      [x] 98.1.2.3 Subtask - Generate or copy the initial shadcn-vue primitive set needed for buttons, badges, alerts, tabs, tables, dialogs, popovers, command menus, inputs, empty states, select controls, scroll areas, skeletons, and tooltips.

  [x] 98.2 Section - CSS Token And Theme Foundation
    Replace DaisyUI theme variables with shadcn-aligned tokens shared by HEEx and Vue.

    [x] 98.2.1 Task - Rebuild `assets/css/app.css` around shared tokens.
      Make Tailwind v4, Phoenix sources, and shadcn-style variables the official styling foundation.

      [x] 98.2.1.1 Subtask - Preserve required Tailwind v4 import and `@source` directives for app CSS, JS, Vue, and `lib/jido_code_web`.
      [x] 98.2.1.2 Subtask - Add light, dark, and system-compatible CSS variables for background, foreground, card, popover, primary, secondary, muted, accent, destructive, border, input, ring, sidebar, and radius tokens.
      [x] 98.2.1.3 Subtask - Add small `.ui-*` utility component classes only where the HEEx side needs stable non-generated classes.

    [x] 98.2.2 Task - Remove DaisyUI from the official path.
      Stop relying on DaisyUI CSS themes now, prevent new class references, and keep npm removal gated until existing runtime references are rewritten.

      [x] 98.2.2.1 Subtask - Remove DaisyUI plugin imports and theme blocks from `assets/css/app.css`.
      [x] 98.2.2.2 Subtask - Keep DaisyUI npm removal gated by the Phase 97 policy until first-party runtime references are zero.
      [x] 98.2.2.3 Subtask - Add guard coverage that fails on new DaisyUI classes in first-party HEEx, Vue, CSS, and tests.

  [ ] 98.3 Section - LiveView And LiveVue Boundary Cleanup
    Align shared component imports and Vue island registration with the new split.

    [ ] 98.3.1 Task - Introduce the app-owned SaladUI boundary.
      Keep LiveViews from depending directly on SaladUI module internals.

      [ ] 98.3.1.1 Subtask - Alias `JidoCodeWeb.Components.UI` from `JidoCodeWeb.html_helpers/0`.
      [ ] 98.3.1.2 Subtask - Delegate only adopted primitives and leave forms or inputs on existing Phoenix core components unless explicitly replaced.
      [ ] 98.3.1.3 Subtask - Document that customized HEEx primitives should move under app-owned component modules rather than direct `SaladUI.*` imports in LiveViews.

    [ ] 98.3.2 Task - Make the Vue island registry explicit.
      Keep shadcn-vue primitives private to Vue islands and avoid broad glob mounting.

      [ ] 98.3.2.1 Subtask - Replace `import.meta.glob` LiveVue discovery with an explicit production island registry.
      [ ] 98.3.2.2 Subtask - Add `assets/vue/lib/utils.ts` with `cn()` using `clsx` and `tailwind-merge`.
      [ ] 98.3.2.3 Subtask - Add tests proving `assets/vue/components/ui` primitives and example components are not direct LiveVue mount targets.

  [ ] 98.4 Section - Integration Tests
    End the phase by proving the new dependency, CSS, HEEx, and Vue primitive boundaries compile and fail safely.

    [ ] 98.4.1 Task - Add frontend stack contract tests.
      Verify the foundation matches the ariston-style split and cannot drift back to DaisyUI.

      [ ] 98.4.1.1 Subtask - Assert `components.json` targets the Phoenix asset layout and shadcn-vue aliases.
      [ ] 98.4.1.2 Subtask - Assert app CSS exposes shadcn-aligned tokens without DaisyUI plugin usage.
      [ ] 98.4.1.3 Subtask - Assert SaladUI dependency, `TwMerge.Cache`, and `JidoCodeWeb.Components.UI` delegates are present.

    [ ] 98.4.2 Task - Verify browser and SSR primitives.
      Prove generated Vue primitives render through the LiveVue pipeline without becoming route owners.

      [ ] 98.4.2.1 Subtask - Add Vitest or equivalent SSR coverage for a shadcn-vue primitive preview.
      [ ] 98.4.2.2 Subtask - Add registry tests proving only production islands are mountable.
      [ ] 98.4.2.3 Subtask - Run `mix frontend.verify` and focused LiveVue component tests.
