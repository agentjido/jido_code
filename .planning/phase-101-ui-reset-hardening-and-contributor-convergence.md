# Phase 101 - UI Reset Hardening And Contributor Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces -->
<!-- covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands -->
<!-- covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `README.md`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `docs/developer/09-frontend-and-product-surfaces.md`
- `docs/developer/10-development-workflow-and-quality-gates.md`
- `assets/css/app.css`
- `assets/vue/index.ts`
- `assets/vue/components/ui/`
- `lib/jido_code_web/components/layouts.ex`
- `lib/jido_code_web/components/ui.ex`
- `lib/jido_code_web/components/live_vue_components.ex`
- `test/e2e/`
- `test/jido_code_web/live/`
- `.github/workflows/ci.yml`

## Relevant Assumptions / Defaults
- Phases 97 through 100 have rebuilt the UI stack, routing shell, product surfaces, and retained Vue islands.
- The final product should have one official browser architecture: LiveView-owned area shell, SaladUI-backed HEEx primitives, and generated shadcn-vue primitives inside bounded LiveVue islands.
- DaisyUI, the old subject-tree shell, broad Vue auto-registration, and old route-local chrome are not current truth after this phase.
- Operator paths must remain usable when SSR, Vite assets, or Vue island delivery degrade.
- Contributor guidance and quality gates should make the new UI stack obvious for future work.

[x] 101 Phase 101 - UI Reset Hardening And Contributor Convergence
  Harden the replacement UI as the durable default and update docs, tests, and quality gates so contributors do not recreate the old stack.

  [x] 101.1 Section - Resilience, Accessibility, And Browser Hardening
    Verify the new shell and islands behave across realistic browser states and degraded delivery.

    [x] 101.1.1 Task - Harden responsive and accessible shell behavior.
      Make the new button-menu shell work for keyboard, screen-reader, mobile, and desktop users.

      [x] 101.1.1.1 Subtask - Add accessibility labels, `aria-current`, focus states, landmarks, and status-strip live regions across the root shell.
      [x] 101.1.1.2 Subtask - Verify button-menu wrapping, area content stacking, and detail-route layout on mobile and desktop breakpoints.
      [x] 101.1.1.3 Subtask - Ensure text does not overflow buttons, status badges, tables, or shell panels under long repo, work item, and provider names.

    [x] 101.1.2 Task - Harden LiveVue degradation paths.
      Keep operator workflows legible when richer browser regions fail.

      [x] 101.1.2.1 Subtask - Verify SSR-disabled, SSR-failed, manifest-missing, and client-asset-failed modes produce product-oriented fallback content.
      [x] 101.1.2.2 Subtask - Ensure server-owned core actions remain reachable when optional Vue islands degrade.
      [x] 101.1.2.3 Subtask - Surface frontend degradation evidence through shell status or bounded panel messaging instead of raw Vite or SSR errors.

  [x] 101.2 Section - Documentation And Contributor Guidance
    Replace old frontend guidance with the final UI reset architecture.

    [x] 101.2.1 Task - Update contributor-facing docs.
      Make the new stack and decision rules clear at the normal entrypoints.

      [x] 101.2.1.1 Subtask - Update README, CONTRIBUTING, and AGENTS to describe the SaladUI HEEx boundary, shadcn-vue generated assets, explicit LiveVue registry, and area shell.
      [x] 101.2.1.2 Subtask - Update developer docs to say when to use Phoenix core components, `JidoCodeWeb.Components.UI`, and Vue primitives.
      [x] 101.2.1.3 Subtask - Document how to add a new area, a new SaladUI wrapper, and a new shadcn-vue island without reviving broad auto-registration.

    [x] 101.2.2 Task - Update quality gates and CI.
      Make the new frontend reset enforceable.

      [x] 101.2.2.1 Subtask - Add or update `mix frontend.verify` coverage for generated Vue primitives, explicit island registry, and CSS token checks.
      [x] 101.2.2.2 Subtask - Add CI checks that fail on DaisyUI dependencies, DaisyUI component classes, or old shell module imports.
      [x] 101.2.2.3 Subtask - Keep the fast local loop practical by separating focused UI reset checks from broader semantic, memory, and runtime gates unless those boundaries are touched.

  [x] 101.3 Section - Final Cleanup And Current Truth Alignment
    Remove remaining obsolete artifacts and make the reset the only documented UI truth.

    [x] 101.3.1 Task - Clean up superseded modules and tests.
      Delete drift-prone leftovers after coverage proves the replacement behavior.

      [x] 101.3.1.1 Subtask - Remove unused operator-navigation, subject-tree, DaisyUI utility, and old Vue-widget modules.
      [x] 101.3.1.2 Subtask - Replace or delete tests that assert old markup instead of product behavior.
      [x] 101.3.1.3 Subtask - Remove generated public assets or stale lockfile entries that are no longer part of the new stack.

    [x] 101.3.2 Task - Align specs, decisions, and planning notes.
      Make the UI reset visible in the repo’s current-truth surfaces.

      [x] 101.3.2.1 Subtask - Update frontend architecture specs or docs to supersede Phase 12 through Phase 15 incremental adoption language where it conflicts with the reset.
      [x] 101.3.2.2 Subtask - Update operator-surface guidance to describe the area button menu shell instead of the old subject-tree shell.
      [x] 101.3.2.3 Subtask - Add a chronology note explaining that Phases 97 through 101 supersede the previous DaisyUI and subject-tree UI implementation.

  [x] 101.4 Section - Integration Tests
    End the track with end-to-end verification that the reset is complete and durable.

    [x] 101.4.1 Task - Run final browser and accessibility verification.
      Verify the new UI behaves as a complete product shell, not just compiled components.

      [x] 101.4.1.1 Subtask - Run Playwright smoke coverage for public bootstrap, authenticated root area navigation, detail routes, settings, and degraded Vue island delivery.
      [x] 101.4.1.2 Subtask - Add accessibility-focused assertions for area navigation, table labels, dialogs, popovers, command menus, status strips, and fallback panels.
      [x] 101.4.1.3 Subtask - Capture desktop and mobile screenshots for the root shell and representative dense routes.

    [x] 101.4.2 Task - Run final contributor and regression gates.
      Verify the repo has converged on the new UI reset architecture.

      [x] 101.4.2.1 Subtask - Run `mix frontend.verify`, focused LiveView UI suites, and browser tests.
      [x] 101.4.2.2 Subtask - Run `mix semantic.verify`, `mix memory.verify`, or `mix runtime.verify` only if UI rebuild work touched those product boundaries.
      [x] 101.4.2.3 Subtask - Run final no-DaisyUI, no-old-shell, explicit-island-registry, and documentation-current-truth checks.
