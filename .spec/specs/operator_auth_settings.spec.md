# Operator Auth Settings

This subject defines the authenticated landing-page operator console used to configure hosted provider login separately from deployment-local Git provider automation. It is part of the repo-local auth-provider foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

```spec-meta
id: auth.operator_settings
kind: feature
status: active
summary: authenticated operators can manage provider-login broker trust on the landing page, see GitHub automation readiness separately, and keep Git service secrets distinct from provider-login configuration.
surface:
  - lib/jido_code_web/live/home_live.ex
  - test/jido_code_web/live/home_live_operator_settings_test.exs
```

## Requirements

```spec-requirements
- id: auth.operator_settings.sections_separated
  statement: The authenticated landing page shall present separate Provider Login and Git Provider Integrations sections.
  priority: must
  stability: stable

- id: auth.operator_settings.broker_trust_configuration_ui
  statement: The Provider Login section shall let an operator persist provider-host enablement, allowlist posture, and broker trust fields without collecting Git automation secrets in the same form.
  priority: must
  stability: evolving

- id: auth.operator_settings.github_service_validation_feedback
  statement: The Git Provider Integrations section shall show GitHub automation readiness feedback, including path-level validation detail and remediation, using deployment-local credential checks.
  priority: must
  stability: evolving

- id: auth.operator_settings.integration_boundary_visible
  statement: The operator console shall make the boundary explicit between provider-login broker configuration and deployment-local Git service secrets, and it shall keep GitLab and Bitbucket service integrations in explicit placeholder status.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: auth.operator_settings.scenario.operator_views_console
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.integration_boundary_visible
  given:
    - A local operator is already signed in on the baseline landing page.
  when:
    - The operator opens the landing page.
  then:
    - The page shows separate Provider Login and Git Provider Integrations sections and keeps future provider integrations explicit.

- id: auth.operator_settings.scenario.operator_saves_broker_trust
  covers:
    - auth.operator_settings.broker_trust_configuration_ui
  given:
    - A local operator needs to enable hosted provider login.
  when:
    - The operator saves provider-host login settings on the landing page.
  then:
    - The provider config persists broker trust and allowlist fields without storing Git automation secrets.

- id: auth.operator_settings.scenario.operator_refreshes_github_validation
  covers:
    - auth.operator_settings.github_service_validation_feedback
  given:
    - GitHub automation depends on deployment-local credentials.
  when:
    - The operator refreshes GitHub integration validation.
  then:
    - The page renders path-level readiness and remediation feedback separately from provider-login settings.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code_web/live/home_live.ex
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.broker_trust_configuration_ui
    - auth.operator_settings.github_service_validation_feedback
    - auth.operator_settings.integration_boundary_visible

- kind: source_file
  target: test/jido_code_web/live/home_live_operator_settings_test.exs
  covers:
    - auth.operator_settings.sections_separated
    - auth.operator_settings.broker_trust_configuration_ui
    - auth.operator_settings.github_service_validation_feedback
    - auth.operator_settings.integration_boundary_visible
```
