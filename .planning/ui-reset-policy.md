# UI Reset Policy

<!-- covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces -->
<!-- covers: architecture.frontend_stack.daisyui_removed_from_official_path -->
<!-- covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands -->

This policy records the Phase 97.3 implementation rules for the greenfield UI
reset. It keeps the reset from becoming a long-lived mixed UI architecture.

## No-Compatibility Rules

1. No DaisyUI compatibility layer remains after the cutover phase.
2. Old route chrome, subject-tree helpers, operator-navigation helpers, and
   DaisyUI-styled Vue widgets are deleted or rewritten, not hidden behind
   feature flags.
3. LiveView remains the routed host shell. Vue islands stay bounded by
   `JidoCodeWeb.LiveVueComponents.vue_surface/1` and explicit events.
4. SaladUI is reached through app-owned HEEx wrappers such as
   `JidoCodeWeb.Components.UI`, not direct `SaladUI.*` imports in route modules.
5. Generated shadcn-vue primitives live under `assets/vue/components/ui` and are
   imported by production islands. They are not direct LiveVue mount targets.
6. Product service contracts, test fixtures, auth/session behavior, route
   authorization, and LiveVue fallback behavior are preserved.

## Compile-Safe Migration Order

1. Land the dependency, CSS token, SaladUI wrapper, and shadcn-vue primitive
   foundation first.
2. Add the root area shell and button-menu routing contract while current
   product behavior still compiles.
3. Rebuild one product area at a time inside the new shell.
4. Rewrite or delete each retained Vue island as its owning product area is
   rebuilt.
5. Remove old operator shell modules, old route chrome, and old Vue widgets only
   after equivalent product behavior is covered by tests.
6. Remove DaisyUI from npm dependencies only after first-party runtime class
   references are zero.
7. Keep public bootstrap and setup routes working throughout the reset, even if
   their visual replacement lands later than authenticated area routes.

## Stop Conditions

- Do not delete a route before its replacement route or shell area has focused
  LiveView coverage.
- Do not remove a Vue widget before any required semantic-event roundtrip is
  covered by a test.
- Do not remove DaisyUI from `package.json` while first-party HEEx or Vue files
  still use DaisyUI component classes.
- Do not introduce new browser-owned route state to compensate for deleted
  shell helpers.

## Verification Expectations

- Every completed implementation section has its own commit.
- `mix frontend.verify` runs for sections touching dependencies, CSS, Vite, SSR,
  LiveVue helpers, or Vue islands.
- LiveView tests remain the default route verification harness.
- Browser tests cover the final shell navigation, responsive button menu, and
  representative degraded Vue island delivery.
