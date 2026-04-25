# Self-Hosted Provider Auth Integration

This subject defines the reproducible self-hosted behavior for broker-backed provider login and deployment-local GitHub automation in `jido_code`. It is part of the repo-local auth-provider foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

<!-- covers: docs.operator_provider_auth_guide.repo_local_auth_contract_modeled -->

```spec-meta
id: auth.self_hosted_provider_integration
kind: feature
status: active
summary: jido_code makes self-hosted provider login behavior explicit by testing broker-backed GitHub login only after local bootstrap and the signed-in start flow no longer needs to lead, while keeping deployment-local GitHub automation readiness, disabled-login separation, broker failure fallback, and allowlist rejection explicit against the `/welcome` landing flow, whose signed-in ready-state path now behaves as a dashboard-first handoff while lower-page operator controls remain temporarily available there.
surface:
  - lib/jido_code_web/controllers/provider_auth_controller.ex
  - lib/jido_code_web/live/home_live.ex
  - lib/jido_code/github/service_credentials.ex
  - test/jido_code_web/integration/self_hosted_provider_auth_test.exs
```

## Requirements

```spec-requirements
- id: auth.self_hosted_provider_integration.login_and_service_ready
  statement: A self-hosted deployment shall support broker-backed GitHub login while deployment-local GitHub automation validation is simultaneously ready.
  priority: must
  stability: evolving

- id: auth.self_hosted_provider_integration.service_independent_of_login_toggle
  statement: GitHub automation validation shall remain available even when browser provider login is disabled for that provider host.
  priority: must
  stability: stable

- id: auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
  statement: Local email authentication shall remain available when broker validation is unavailable or fails for provider login.
  priority: must
  stability: stable

- id: auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
  statement: Provider-login allowlist rejection shall block provider session issuance without breaking deployment-local GitHub automation validation.
  priority: must
  stability: evolving

- id: auth.self_hosted_provider_integration.bootstrap_precedes_provider_login
  statement: A self-hosted deployment shall keep local first-admin bootstrap primary and refuse provider login until bootstrap produces a valid local admin state, with the signed-in start surface remaining lighter than a provider-first setup gauntlet.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: auth.self_hosted_provider_integration.scenario.login_and_service_ready
  covers:
    - auth.self_hosted_provider_integration.login_and_service_ready
  given:
    - Provider login is enabled for GitHub.com.
    - Deployment-local GitHub App credentials are configured.
  when:
    - A broker-validated GitHub identity completes sign-in.
  then:
    - The local session is issued and the authenticated landing page shows GitHub automation as ready.

- id: auth.self_hosted_provider_integration.scenario.login_disabled_service_ready
  covers:
    - auth.self_hosted_provider_integration.service_independent_of_login_toggle
  given:
    - Browser provider login is disabled for GitHub.com.
    - Deployment-local GitHub automation credentials remain configured.
  when:
    - An operator inspects the authenticated landing page.
  then:
    - Provider login stays disabled while GitHub automation readiness remains available.

- id: auth.self_hosted_provider_integration.scenario.broker_failure_local_fallback
  covers:
    - auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
  given:
    - Provider login is enabled for GitHub.com.
    - Broker trust validation is unavailable.
  when:
    - Provider sign-in fails.
  then:
    - Local email sign-in and account access remain available.

- id: auth.self_hosted_provider_integration.scenario.allowlist_rejection
  covers:
    - auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
  given:
    - Provider login is enabled and restricted by an allowlist.
    - Deployment-local GitHub automation credentials remain configured.
  when:
    - A provider identity outside the allowlist attempts sign-in.
  then:
    - Provider login is rejected and GitHub automation readiness still renders for the local operator path.

- id: auth.self_hosted_provider_integration.scenario.bootstrap_required
  covers:
    - auth.self_hosted_provider_integration.bootstrap_precedes_provider_login
  given:
    - A brand-new self-hosted install has not yet completed local bootstrap.
  when:
    - An operator tries to start provider login from the public entry surface.
  then:
    - The provider path stays unavailable and the local bootstrap path remains the required public entry route.
    - Signed-in follow-up setup remains optional rather than turning provider login into the next hard gate.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code_web/controllers/provider_auth_controller.ex
  covers:
    - auth.self_hosted_provider_integration.login_and_service_ready
    - auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
    - auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
    - auth.self_hosted_provider_integration.bootstrap_precedes_provider_login

- kind: source_file
  target: lib/jido_code_web/live/home_live.ex
  covers:
    - auth.self_hosted_provider_integration.login_and_service_ready
    - auth.self_hosted_provider_integration.service_independent_of_login_toggle
    - auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
    - auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
    - auth.self_hosted_provider_integration.bootstrap_precedes_provider_login

- kind: source_file
  target: lib/jido_code/github/service_credentials.ex
  covers:
    - auth.self_hosted_provider_integration.login_and_service_ready
    - auth.self_hosted_provider_integration.service_independent_of_login_toggle
    - auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression

- kind: source_file
  target: test/jido_code_web/integration/self_hosted_provider_auth_test.exs
  covers:
    - auth.self_hosted_provider_integration.login_and_service_ready
    - auth.self_hosted_provider_integration.service_independent_of_login_toggle
    - auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
    - auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
    - auth.self_hosted_provider_integration.bootstrap_precedes_provider_login
```
