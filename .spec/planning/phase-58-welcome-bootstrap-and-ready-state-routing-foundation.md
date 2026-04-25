# Phase 58 - Welcome Bootstrap And Ready-State Routing Foundation

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/provider_login_flow.spec.md`
- `../specs/user_administration.spec.md`
- `../decisions/jido_code.auth_user_system.md`
- `../decisions/jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff.md`
- `lib/jido_code/setup/bootstrap_status.ex`
- `lib/jido_code_web/router.ex`
- `lib/jido_code_web/controllers/page_controller.ex`
- `lib/jido_code_web/controllers/auth_controller.ex`
- `lib/jido_code_web/live_user_auth.ex`
- `lib/jido_code_web/live/home_live.ex`
- `lib/jido_code_web/live/setup_live.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `test/jido_code_web/controllers/page_controller_test.exs`
- `test/jido_code_web/live/home_live_test.exs`
- `test/jido_code_web/live/setup_live_test.exs`

## Relevant Assumptions / Defaults
- `/welcome` remains the canonical public and bootstrap-facing route throughout this phase.
- `/setup` remains the signed-in continuation surface while bootstrap or onboarding follow-up is incomplete.
- The current implementation still defaults ready-state local sign-in back to `/welcome`, so this phase is the routing cutover that changes that behavior.
- Provider-login entry stays on `/welcome` for anonymous or signed-out users when bootstrap is complete and provider login is configured.

[ ] 58 Phase 58 - Welcome Bootstrap And Ready-State Routing Foundation
  Establish the routing, redirect, and ready-state `/welcome` behavior that lets bootstrap stay public-facing while authenticated ready-state sessions hand off into the product instead of reopening the welcome-page operator console by default.

  [ ] 58.1 Section - Default Route And Redirect Ownership
    Cut over authenticated ready-state routing without disturbing bootstrap-required or continue-setup behavior.

    [ ] 58.1.1 Task - Reframe the default authenticated handoff around dashboard and setup state
      Make the route contract explicit so bootstrap-required, continue-setup, and ready deployments each land on the right surface.

      [ ] 58.1.1.1 Subtask - Keep `/` redirecting to `/welcome` so the public/bootstrap entry route remains canonical.
      [ ] 58.1.1.2 Subtask - Change ready-state local-auth success to default to `/dashboard` while preserving explicit `return_to` overrides.
      [ ] 58.1.1.3 Subtask - Preserve `:continue_setup` handoff into `/setup` and avoid routing partially configured installs into dashboard.

    [ ] 58.1.2 Task - Align auth-boundary redirects with the cutover
      Keep protected-route and post-auth behavior coherent once ready-state logins stop reopening the full welcome surface.

      [ ] 58.1.2.1 Subtask - Keep unauthenticated access to protected routes redirecting through `/welcome`.
      [ ] 58.1.2.2 Subtask - Preserve signed-in `:continue_setup` redirects to `/setup` from protected product routes.
      [ ] 58.1.2.3 Subtask - Ensure sign-out and auth failure states still return operators to the public `/welcome` entry route rather than an authenticated-only surface.

  [ ] 58.2 Section - Welcome Surface Slimming And Handoff Copy
    Reduce the ready-state `/welcome` experience to a bootstrap and sign-in handoff surface instead of a permanent operator console.

    [ ] 58.2.1 Task - Remove full ready-state operator-console ownership from `/welcome`
      Reshape `HomeLive` so the route remains state-aware and useful without being the durable destination for provider and integration management.

      [ ] 58.2.1.1 Subtask - Keep first-run bootstrap and anonymous sign-in entry behavior unchanged on `/welcome`.
      [ ] 58.2.1.2 Subtask - Replace the ready-state operator settings console with compact handoff-oriented content for dashboard and settings entry.
      [ ] 58.2.1.3 Subtask - Keep runtime health or readiness notes transparent unless they block bootstrap or sign-in progress.

    [ ] 58.2.2 Task - Preserve provider-login discoverability on the public landing
      Keep GitHub provider entry visible in the correct state while separating it from the authenticated operator settings destination.

      [ ] 58.2.2.1 Subtask - Continue exposing provider-login entry on `/welcome` only after bootstrap is complete and provider login is enabled.
      [ ] 58.2.2.2 Subtask - Keep local email sign-in as the durable fallback on the public route when provider login is unavailable or disabled.
      [ ] 58.2.2.3 Subtask - Ensure ready-state signed-in users are guided into dashboard and settings instead of being treated as if `/welcome` were their long-term authenticated home.

  [ ] 58.3 Section - Phase Integration Tests
    Prove the routing cutover and slimmer welcome route behave correctly across bootstrap, continue-setup, and ready-state authentication.

    [ ] 58.3.1 Task - Add route and auth integration coverage for the new handoff rules
      Verify the route matrix at the browser and LiveView boundary instead of relying on controller logic alone.

      [ ] 58.3.1.1 Subtask - Cover root, sign-in, sign-out, and protected-route redirect behavior for bootstrap-required, continue-setup, and ready states.
      [ ] 58.3.1.2 Subtask - Cover ready-state login defaulting to `/dashboard` while explicit `return_to` values still win.
      [ ] 58.3.1.3 Subtask - Cover `/welcome` rendering as bootstrap/auth handoff content instead of a full ready-state operator console.
