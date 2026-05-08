# Phase 60 - Welcome Dashboard And Settings Convergence

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/baseline_surface.spec.md`
- `../specs/operator_auth_settings.spec.md`
- `../specs/provider_login_flow.spec.md`
- `../specs/user_administration.spec.md`
- `../specs/setup_onboarding.spec.md`
- `../specs/operator_provider_auth_guide.spec.md`
- `../decisions/jido_code.auth_user_system.md`
- `../decisions/jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff.md`
- `lib/jido_code_web/controllers/auth_controller.ex`
- `lib/jido_code_web/controllers/provider_auth_controller.ex`
- `lib/jido_code_web/live/home_live.ex`
- `lib/jido_code_web/live/setup_live.ex`
- `lib/jido_code_web/live/dashboard_live.ex`
- `lib/jido_code_web/live/settings_live.ex`
- `test/jido_code_web/controllers/provider_auth_controller_test.exs`
- `test/jido_code_web/live/home_live_test.exs`
- `test/jido_code_web/live/setup_live_test.exs`
- `test/jido_code_web/live/dashboard_live_test.exs`
- `test/jido_code_web/live/settings_live_test.exs`

## Relevant Assumptions / Defaults
- By the end of Phase 59, `/welcome` is no longer the durable home of the operator auth-settings console.
- The dashboard is already a real authenticated product surface and setup completion already hands off there explicitly.
- Provider-backed sign-in must continue to honor validated redirect contracts and explicit return paths, even as the ready-state default destination changes.
- Current-truth specs should only be tightened to the final destination behavior once the implementation actually lands.

[x] 60 Phase 60 - Welcome Dashboard And Settings Convergence
  Complete the product-entry cutover by making dashboard the durable authenticated landing, keeping settings as the home of operator configuration, and then reconciling tests, docs, and current-truth specs to the shipped behavior.

  [x] 60.1 Section - Final Authenticated Entry Convergence
    Align local auth, provider auth, onboarding completion, and repeat visits so the post-bootstrap product entry model is consistent everywhere.

    [x] 60.1.1 Task - Finalize dashboard as the ready-state default destination
      Make all steady-state authenticated entry paths agree on dashboard unless a more specific return path is already in force.

      [x] 60.1.1.1 Subtask - Keep setup completion routing into `/dashboard` as the canonical post-onboarding handoff.
      [x] 60.1.1.2 Subtask - Align local and provider-backed sign-in defaults so ready-state sessions land on `/dashboard` unless an explicit redirect override is present.
      [x] 60.1.1.3 Subtask - Preserve `/setup` as the only signed-in continuation path for incomplete onboarding rather than letting ready-state dashboard defaults leak backward.

    [x] 60.1.2 Task - Make welcome, dashboard, and settings feel like one coherent entry model
      Remove the last product-language contradictions so the public landing, product overview, and operator settings each have a clear job.

      [x] 60.1.2.1 Subtask - Keep `/welcome` focused on bootstrap, sign-in, and handoff language rather than product-overview or durable settings language.
      [x] 60.1.2.2 Subtask - Keep dashboard positioned as the authenticated product overview rather than an onboarding-only success screen.
      [x] 60.1.2.3 Subtask - Keep settings positioned as the durable home for operator-managed provider and integration configuration.

  [x] 60.2 Section - Current-Truth, Docs, And Contributor Convergence
    Tighten specs and user-facing guidance only after the final route and settings cutover is real in product code.

    [x] 60.2.1 Task - Reconcile specs and ADR-linked subjects to shipped behavior
      Promote the accepted handoff decision from planned future state into explicit current truth once the implementation has landed.

      [x] 60.2.1.1 Subtask - Update baseline-surface, provider-login-flow, operator-auth-settings, and user-administration specs to describe the final routed ownership and destinations.
      [x] 60.2.1.2 Subtask - Reconcile any remaining setup, auth-guide, or package-level spec language that still implies `/welcome` is the durable ready-state operator home.
      [x] 60.2.1.3 Subtask - Record any additional durable route or settings-boundary ADR only if implementation reveals a new architectural rule beyond the accepted handoff decision.

    [x] 60.2.2 Task - Align operator-facing copy and contributor guidance
      Remove stale wording that still describes disabled product routes or the welcome page as the permanent operator console.

      [x] 60.2.2.1 Subtask - Update welcome, dashboard, and settings copy so operators understand where to go after bootstrap and sign-in.
      [x] 60.2.2.2 Subtask - Update contributor-facing guidance and planning references that describe the public landing, authenticated product entry, or operator-settings home.
      [x] 60.2.2.3 Subtask - Keep deployment-specific operator guidance repo-local only where it clarifies the in-product route contract rather than becoming a full external setup manual.

  [x] 60.3 Section - Phase Integration Tests
    Close the implementation plan with end-to-end coverage that proves the final entry model is coherent across bootstrap, onboarding, repeated sign-in, and operator configuration.

    [x] 60.3.1 Task - Add end-to-end route and settings convergence coverage
      Verify the final flow as an operator would actually experience it after the full cutover.

      [x] 60.3.1.1 Subtask - Cover first-run bootstrap into signed-in setup continuation and explicit completion into dashboard.
      [x] 60.3.1.2 Subtask - Cover subsequent ready-state local and provider sign-in landing on dashboard while provider and Git integration management lives under settings.
      [x] 60.3.1.3 Subtask - Cover direct navigation among `/welcome`, `/dashboard`, and the settings-owned auth-and-integrations destination so the final route ownership is stable and unsurprising.
