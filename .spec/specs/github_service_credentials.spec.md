# GitHub Service Credentials

This subject defines the deployment-local GitHub automation credential boundary and keeps it separate from provider-login broker configuration. It is part of the repo-local foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

<!-- covers: docs.operator_provider_auth_guide.repo_local_auth_contract_modeled -->

```spec-meta
id: auth.github_service_credentials
kind: feature
status: active
summary: jido_code keeps GitHub automation credentials deployment-local, names them through canonical SecretRefs, and does not reuse provider-login broker configuration for automation.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/github/service_credentials.ex
  - lib/jido_code/setup/github_credential_checks.ex
  - lib/jido_code/github/webhook_signature.ex
  - test/jido_code/github/service_credentials_test.exs
```

## Requirements

```spec-requirements
- id: auth.github_service_credentials.secret_ref_names
  statement: GitHub automation credentials shall use canonical deployment-local SecretRef names for GitHub App ID, GitHub App private key, GitHub webhook secret, and PAT fallback.
  priority: must
  stability: stable

- id: auth.github_service_credentials.login_service_split
  statement: Provider-login broker configuration shall remain distinct from deployment-local GitHub automation credentials and shall not be reused as the automation credential source.
  priority: must
  stability: stable

- id: auth.github_service_credentials.secret_resolution
  statement: GitHub automation runtime callers shall resolve deployment-local credentials from environment or encrypted SecretRefs without depending on provider-login configuration state.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: auth.github_service_credentials.scenario_env_overrides_secret_ref
  covers:
    - auth.github_service_credentials.secret_resolution
  given:
    - A deployment-local GitHub automation secret exists in encrypted SecretRefs.
    - The same credential is also present in root environment configuration.
  when:
    - GitHub automation resolves that credential.
  then:
    - The root environment value wins and the secret-ref metadata remains non-authoritative for that resolution.

- id: auth.github_service_credentials.scenario_secret_ref_fallback
  covers:
    - auth.github_service_credentials.secret_ref_names
    - auth.github_service_credentials.secret_resolution
  given:
    - A deployment-local GitHub automation secret is absent from runtime env and present in encrypted SecretRefs under its canonical name.
  when:
    - GitHub automation resolves that credential.
  then:
    - The encrypted SecretRef value is used.

- id: auth.github_service_credentials.scenario_login_broker_separated
  covers:
    - auth.github_service_credentials.login_service_split
  given:
    - Provider-login configuration is stored in the provider config model.
  when:
    - GitHub automation service credentials are described for setup and runtime callers.
  then:
    - The automation model names deployment-local service secrets separately from provider-login broker fields.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/github/service_credentials.ex
  covers:
    - auth.github_service_credentials.secret_ref_names
    - auth.github_service_credentials.login_service_split
    - auth.github_service_credentials.secret_resolution

- kind: source_file
  target: lib/jido_code/setup/github_credential_checks.ex
  covers:
    - auth.github_service_credentials.login_service_split

- kind: source_file
  target: lib/jido_code/github/webhook_signature.ex
  covers:
    - auth.github_service_credentials.secret_resolution

- kind: source_file
  target: test/jido_code/github/service_credentials_test.exs
  covers:
    - auth.github_service_credentials.secret_ref_names
    - auth.github_service_credentials.login_service_split
    - auth.github_service_credentials.secret_resolution
```
