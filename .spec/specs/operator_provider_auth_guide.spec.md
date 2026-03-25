# Operator Provider Auth Guide

This subject defines the operator-facing documentation required to configure self-hosted provider login and deployment-local GitHub automation in `jido_code`. It is part of the repo-local auth-provider foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

```spec-meta
id: docs.operator_provider_auth_guide
kind: feature
status: active
summary: jido_code publishes an operator guide that explains broker-managed GitHub login, deployment-local GitHub service credentials, callback and allowlist behavior, and future GitLab or Bitbucket posture without requiring operators to read implementation code.
surface:
  - docs/self_hosted_provider_auth.md
```

## Requirements

```spec-requirements
- id: docs.operator_provider_auth_guide.github_broker_registration_steps
  statement: The operator guide shall describe the exact GitHub login app registration fields used for the broker-managed login model.
  priority: must
  stability: evolving

- id: docs.operator_provider_auth_guide.github_service_credential_setup
  statement: The operator guide shall describe deployment-local GitHub service credential setup, including canonical SecretRef names and supported environment variables.
  priority: must
  stability: stable

- id: docs.operator_provider_auth_guide.callback_and_allowlist_explained
  statement: The operator guide shall explain the callback, redirect, signed-state, and allowlist flow for self-hosted provider login.
  priority: must
  stability: stable

- id: docs.operator_provider_auth_guide.future_provider_notes
  statement: The operator guide shall explain the current future-provider posture for GitLab and Bitbucket so operators do not assume those integrations are production-ready yet.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: docs.operator_provider_auth_guide.scenario.github_login_setup
  covers:
    - docs.operator_provider_auth_guide.github_broker_registration_steps
    - docs.operator_provider_auth_guide.callback_and_allowlist_explained
  given:
    - An operator needs to enable hosted GitHub login for a self-hosted deployment.
  when:
    - The operator reads the provider auth guide.
  then:
    - The guide explains the broker-managed callback model and the exact deployment-side fields to configure.

- id: docs.operator_provider_auth_guide.scenario.github_service_setup
  covers:
    - docs.operator_provider_auth_guide.github_service_credential_setup
  given:
    - An operator needs GitHub automation to work in the same deployment.
  when:
    - The operator reads the provider auth guide.
  then:
    - The guide lists the deployment-local secrets, env vars, and readiness expectations without mixing them into broker login config.

- id: docs.operator_provider_auth_guide.scenario.future_provider_expectations
  covers:
    - docs.operator_provider_auth_guide.future_provider_notes
  given:
    - An operator is evaluating GitLab and Bitbucket.
  when:
    - The operator reads the provider auth guide.
  then:
    - The guide makes it clear that those providers are modeled but not operator-ready end to end yet.
```

## Verification

```spec-verification
- kind: source_file
  target: docs/self_hosted_provider_auth.md
  covers:
    - docs.operator_provider_auth_guide.github_broker_registration_steps
    - docs.operator_provider_auth_guide.github_service_credential_setup
    - docs.operator_provider_auth_guide.callback_and_allowlist_explained
    - docs.operator_provider_auth_guide.future_provider_notes
```
