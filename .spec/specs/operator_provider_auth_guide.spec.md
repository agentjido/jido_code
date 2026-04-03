# Operator Provider Auth Guide

This subject defines the repo-local boundary around self-hosted provider login and deployment-local GitHub automation guidance in `jido_code`. The full step-by-step operator prose may live outside this repo, but the repo must keep the implementation contract and contributor-facing separation current.

<!-- covers: package.jido_code.auth_provider_foundation_in_repo -->

```spec-meta
id: docs.operator_provider_auth_guide
kind: feature
status: active
summary: jido_code keeps the operator auth contract modeled in repo-local specs while allowing the detailed step-by-step operator prose to live outside the repository, even as contributor-facing README guidance grows to cover the approved frontend stack, repo-owned `mix server` start path, and verification path.
surface:
  - README.md
  - .spec/specs/operator_auth_settings.spec.md
  - .spec/specs/github_service_credentials.spec.md
  - .spec/specs/self_hosted_provider_integration.spec.md
```

The repo-facing README may index local contributor and architecture guides, but it shall not imply that a detailed in-repo operator provider-auth setup guide exists.

## Requirements

```spec-requirements
- id: docs.operator_provider_auth_guide.local_quickstart_excludes_operator_setup
  statement: Contributor-facing quickstart docs shall keep deployment-specific provider-login setup out of the normal local development path.
  priority: must
  stability: evolving

- id: docs.operator_provider_auth_guide.repo_local_auth_contract_modeled
  statement: The repository shall keep the self-hosted provider auth, GitHub service-credential, and callback/allowlist contract modeled in repo-local specs even when the prose operator guide is maintained outside the repository.
  priority: must
  stability: stable

- id: docs.operator_provider_auth_guide.external_operator_docs_allowed
  statement: The repository may keep the detailed operator prose outside the repo as long as repo-local docs do not claim an in-repo guide exists.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: docs.operator_provider_auth_guide.scenario.github_login_setup
  covers:
    - docs.operator_provider_auth_guide.local_quickstart_excludes_operator_setup
    - docs.operator_provider_auth_guide.repo_local_auth_contract_modeled
  given:
    - An operator needs to enable hosted GitHub login for a self-hosted deployment.
  when:
    - The operator inspects the repo-local guidance and specs.
  then:
    - The local developer quickstart stays clean, and the repo-local specs still capture the underlying login and callback contract.

- id: docs.operator_provider_auth_guide.scenario.github_service_setup
  covers:
    - docs.operator_provider_auth_guide.repo_local_auth_contract_modeled
  given:
    - An operator needs GitHub automation to work in the same deployment.
  when:
    - The operator inspects the repo-local specs.
  then:
    - The repo still captures the deployment-local secrets, env vars, and readiness expectations without mixing them into the contributor quickstart.

- id: docs.operator_provider_auth_guide.scenario.future_provider_expectations
  covers:
    - docs.operator_provider_auth_guide.external_operator_docs_allowed
  given:
    - A maintainer keeps detailed operator prose outside the repo.
  when:
    - The maintainer updates the repo-facing docs.
  then:
    - The repo does not advertise a missing in-repo operator guide.
```

## Verification

```spec-verification
- kind: source_file
  target: README.md
  covers:
    - docs.operator_provider_auth_guide.local_quickstart_excludes_operator_setup
    - docs.operator_provider_auth_guide.external_operator_docs_allowed

- kind: source_file
  target: .spec/specs/operator_auth_settings.spec.md
  covers:
    - docs.operator_provider_auth_guide.repo_local_auth_contract_modeled

- kind: source_file
  target: .spec/specs/github_service_credentials.spec.md
  covers:
    - docs.operator_provider_auth_guide.repo_local_auth_contract_modeled

- kind: source_file
  target: .spec/specs/self_hosted_provider_integration.spec.md
  covers:
    - docs.operator_provider_auth_guide.repo_local_auth_contract_modeled
```
