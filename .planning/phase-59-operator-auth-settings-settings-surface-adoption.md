# Phase 59 - Operator Auth Settings Settings-Surface Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/operator_auth_settings.spec.md`
- `../specs/provider_auth_foundation.spec.md`
- `../specs/operator_provider_auth_guide.spec.md`
- `../specs/provider_login_flow.spec.md`
- `../decisions/jido_code.auth_user_system.md`
- `../decisions/jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff.md`
- `lib/jido_code/auth_providers/provider_config.ex`
- `lib/jido_code/auth_providers/provider_login.ex`
- `lib/jido_code/github/service_credentials.ex`
- `lib/jido_code/source_providers/github_adapter.ex`
- `lib/jido_code_web/live/home_live.ex`
- `lib/jido_code_web/live/settings_live.ex`
- `lib/jido_code_web/router.ex`
- `test/jido_code_web/live/home_live_operator_settings_test.exs`
- `test/jido_code_web/live/settings_live_test.exs`

## Relevant Assumptions / Defaults
- Provider Login and Git Provider Integrations remain one operator boundary while moving from the ready-state welcome view onto a settings-owned authenticated surface.
- The settings route already exists and is the intended durable authenticated home for operator-managed configuration.
- This phase should preserve the separation between provider-login broker trust and deployment-local Git automation credentials instead of collapsing them into one generic secrets form.
- The public `/welcome` route should not regain ownership of durable operator configuration once this migration begins.

[x] 59 Phase 59 - Operator Auth Settings Settings-Surface Adoption
  Move provider-login and Git provider integration management onto a settings-owned authenticated surface so durable operator configuration no longer depends on the ready-state welcome view.

  [x] 59.1 Section - Settings Information Architecture And Route Ownership
    Give auth and integration management a durable home inside `/settings` without weakening the current route and permissions model.

    [x] 59.1.1 Task - Introduce a settings-owned auth-and-integrations destination
      Create an explicit settings tab, section, or equivalent route-owned destination for the operator auth-settings console.

      [x] 59.1.1.1 Subtask - Add a stable `/settings` destination for Provider Login and Git Provider Integrations that supports direct linking and repeat visits.
      [x] 59.1.1.2 Subtask - Preserve current settings navigation patterns and avoid introducing a second admin-only route family just for auth configuration.
      [x] 59.1.1.3 Subtask - Keep visibility and authorization explicit so only eligible authenticated operators can manage provider and integration settings.

    [x] 59.1.2 Task - Extract reusable auth-settings view models and actions
      Move the durable operator console logic out of `HomeLive` without duplicating persistence or readiness behavior.

      [x] 59.1.2.1 Subtask - Extract provider-login configuration shaping and save actions into settings-owned helpers or boundaries rather than copy-pasting `HomeLive` assigns.
      [x] 59.1.2.2 Subtask - Reuse the existing GitHub credential-check and readiness flow so the settings surface preserves current remediation detail.
      [x] 59.1.2.3 Subtask - Keep the provider-config versus deployment-local service-credential boundary explicit in the extracted implementation and rendered UI.

  [x] 59.2 Section - Welcome-To-Settings Handoff And Surface Cleanup
    Finish the operator-surface split by making `/welcome` point to settings rather than hosting the full operator console itself.

    [x] 59.2.1 Task - Replace welcome-page operator configuration with bounded handoff cues
      Keep `/welcome` useful after sign-in without leaving a second full operator-settings implementation behind.

      [x] 59.2.1.1 Subtask - Remove the full Provider Login and Git Provider Integrations forms and readiness panels from ready-state `HomeLive`.
      [x] 59.2.1.2 Subtask - Replace them with compact status or navigation cues that send operators to the settings-owned destination.
      [x] 59.2.1.3 Subtask - Avoid stale duplicated settings summaries on `/welcome` that could drift from the real settings surface.

    [x] 59.2.2 Task - Keep operator-facing wording and docs coherent during the move
      Align labels and surface copy so operators understand the new home of these controls.

      [x] 59.2.2.1 Subtask - Use consistent naming for Provider Login and Git Provider Integrations across welcome, settings, and related notices.
      [x] 59.2.2.2 Subtask - Keep contributor-facing docs and repo-local specs clear that detailed operator configuration now lives on a settings-owned product surface.
      [x] 59.2.2.3 Subtask - Preserve future GitLab and Bitbucket placeholder treatment on the settings-owned operator console.

  [x] 59.3 Section - Phase Integration Tests
    Verify the settings migration end to end so the operator console remains functional after leaving `/welcome`.

    [x] 59.3.1 Task - Add routed-surface coverage for the settings-owned operator console
      Prove the migrated settings surface preserves persistence, readiness checks, and public-route handoff behavior.

      [x] 59.3.1.1 Subtask - Cover direct navigation to the settings auth-and-integrations destination and visibility rules for eligible operators.
      [x] 59.3.1.2 Subtask - Cover provider-login save flows and GitHub readiness refresh flows on the settings-owned surface.
      [x] 59.3.1.3 Subtask - Cover `/welcome` offering only compact handoff cues after the console has moved.
