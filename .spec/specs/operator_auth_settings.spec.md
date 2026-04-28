# Operator Auth Settings

<!-- current_truth.reconciled_with_branch: the settings-owned auth-and-integrations destination remains the durable home for provider-login broker trust and GitHub automation readiness, the sibling `/settings/github` add-repository modal now routes later GitHub additions through the canonical managed-repository import boundary instead of treating settings-only rows as product truth, and that settings-owned operator surface now participates in the shared signed-in navigation layer rather than relying on ad hoc header handoff links. -->

This subject defines the current operator auth-settings console used to configure hosted provider login separately from deployment-local Git provider automation. It is part of the repo-local auth-provider foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

<!-- covers: docs.operator_provider_auth_guide.repo_local_auth_contract_modeled -->

```spec-meta
id: auth.operator_settings
kind: feature
status: active
summary: authenticated operators can manage provider-login broker trust and GitHub automation readiness through a settings-owned authenticated auth-and-integrations surface, keep Git service secrets distinct from provider-login configuration, reach that console through durable settings navigation once bootstrap is complete and ready-state auth has entered dashboard, participate in the shared signed-in operator navigation model, and coexist with a sibling `/settings/github` repository-add flow that imports canonical managed repositories rather than creating a separate auth-settings truth lane, while signed-in `/welcome` stays only a compact handoff into dashboard and `/settings/auth`.
decisions:
  - jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff
  - jido_code.settings_github_add_repository_uses_managed_repo_import
surface:
  - .spec/decisions/jido_code.settings_github_add_repository_uses_managed_repo_import.md
  - lib/jido_code_web/operator_auth_settings.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code_web/live/settings_live.ex
  - test/support/conn_case.ex
  - test/jido_code_web/live/home_live_operator_settings_test.exs
  - test/jido_code_web/live/phase_fifty_nine_integration_test.exs
  - test/jido_code_web/live/settings_operator_auth_live_test.exs
  - test/jido_code_web/live/phase_fifty_eight_integration_test.exs
  - test/jido_code_web/live/phase_sixty_integration_test.exs
```

## Requirements

```spec-requirements
- id: auth.operator_settings.sections_separated
  statement: The operator auth-settings surface shall present separate Provider Login and Git Provider Integrations sections.
  priority: must
  stability: stable

- id: auth.operator_settings.broker_trust_configuration_ui
  statement: The Provider Login section of the operator auth-settings surface shall let an operator persist provider-host enablement, allowlist posture, and broker trust fields without collecting Git automation secrets in the same form.
  priority: must
  stability: evolving

- id: auth.operator_settings.github_service_validation_feedback
  statement: The Git Provider Integrations section of the operator auth-settings surface shall show GitHub automation readiness feedback, including path-level validation detail and remediation, using deployment-local credential checks.
  priority: must
  stability: evolving

- id: auth.operator_settings.integration_boundary_visible
  statement: The operator console shall make the boundary explicit between provider-login broker configuration and deployment-local Git service secrets, and it shall keep GitLab and Bitbucket service integrations in explicit placeholder status.
  priority: should
  stability: evolving

- id: auth.operator_settings.hidden_during_bootstrap_entry
  statement: The operator auth-settings console shall remain secondary to first-run bootstrap and the lightweight signed-in start surface, only appearing once the deployment is past bootstrap and the ready-state operator surface is allowed to render, with `/settings/auth` as the durable authenticated destination while signed-in `/welcome` remains only a compact handoff into dashboard and settings.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: auth.operator_settings.scenario.operator_views_console
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.integration_boundary_visible
    - auth.operator_settings.hidden_during_bootstrap_entry
  given:
    - A local operator is already signed in on the current ready-state operator surface.
  when:
    - The operator opens the settings-owned auth-and-integrations destination.
  then:
    - The page shows separate Provider Login and Git Provider Integrations sections and keeps future provider integrations explicit.
    - The operator console does not displace the simpler signed-in start path used immediately after bootstrap, because signed-in `/welcome` only offers a compact handoff into settings.
    - The route remains directly revisitable from the authenticated settings navigation instead of depending on the welcome page.

- id: auth.operator_settings.scenario.operator_saves_broker_trust
  covers:
    - auth.operator_settings.broker_trust_configuration_ui
  given:
    - A local operator needs to enable hosted provider login.
  when:
    - The operator saves provider-host login settings on the settings-owned auth-and-integrations surface.
  then:
    - The provider config persists broker trust and allowlist fields without storing Git automation secrets.

- id: auth.operator_settings.scenario.operator_refreshes_github_validation
  covers:
    - auth.operator_settings.github_service_validation_feedback
  given:
    - GitHub automation depends on deployment-local credentials.
  when:
    - The operator refreshes GitHub integration validation on the settings-owned auth-and-integrations surface.
  then:
    - The page renders path-level readiness and remediation feedback separately from provider-login settings.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code_web/operator_auth_settings.ex
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.broker_trust_configuration_ui
    - auth.operator_settings.github_service_validation_feedback
    - auth.operator_settings.integration_boundary_visible

- kind: source_file
  target: lib/jido_code_web/live/home_live.ex
  covers:
    - auth.operator_settings.hidden_during_bootstrap_entry

- kind: source_file
  target: lib/jido_code_web/live/settings_live.ex
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.broker_trust_configuration_ui
    - auth.operator_settings.github_service_validation_feedback
    - auth.operator_settings.integration_boundary_visible
    - auth.operator_settings.hidden_during_bootstrap_entry

- kind: source_file
  target: test/support/conn_case.ex
  covers:
    - auth.operator_settings.hidden_during_bootstrap_entry

- kind: source_file
  target: test/jido_code_web/live/home_live_operator_settings_test.exs
  covers:
    - auth.operator_settings.hidden_during_bootstrap_entry

- kind: source_file
  target: test/jido_code_web/live/settings_operator_auth_live_test.exs
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.broker_trust_configuration_ui
    - auth.operator_settings.github_service_validation_feedback
    - auth.operator_settings.integration_boundary_visible

- kind: source_file
  target: test/jido_code_web/live/phase_fifty_nine_integration_test.exs
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.broker_trust_configuration_ui
    - auth.operator_settings.github_service_validation_feedback
    - auth.operator_settings.integration_boundary_visible
    - auth.operator_settings.hidden_during_bootstrap_entry

- kind: source_file
  target: test/jido_code_web/live/phase_fifty_eight_integration_test.exs
  covers:
    - auth.operator_settings.hidden_during_bootstrap_entry

- kind: source_file
  target: test/jido_code_web/live/phase_sixty_integration_test.exs
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.github_service_validation_feedback
    - auth.operator_settings.hidden_during_bootstrap_entry
```
