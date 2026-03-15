# Provider Auth Foundation

This subject defines the provider-neutral identity and configuration primitives that prepare `jido_code` for brokered OAuth login while preserving local users as the source of truth. It is part of the repo-local foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

```spec-meta
id: auth.provider_foundation
kind: feature
status: active
summary: jido_code persists provider-backed user identities and provider login configuration without replacing the local user system.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/accounts/user_identity.ex
  - lib/jido_code/auth_providers.ex
  - lib/jido_code/auth_providers/provider_config.ex
  - test/jido_code/accounts/user_identity_test.exs
  - test/jido_code/auth_providers/provider_config_test.exs
```

## Requirements

```spec-requirements
- id: auth.provider_foundation.local_user_identity_mapping
  statement: External provider identities shall resolve through a local identity record that uniquely maps provider plus host plus provider subject to one local user.
  priority: must
  stability: stable

- id: auth.provider_foundation.provider_catalog
  statement: The provider auth foundation shall recognize GitHub, GitLab, and Bitbucket as the initial provider catalog.
  priority: must
  stability: stable

- id: auth.provider_foundation.provider_login_configuration
  statement: The system shall persist provider-host login configuration including enablement, allowlist posture, and broker trust fields without coupling it to provider automation secrets.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: auth.provider_foundation.scenario.identity_lookup
  covers:
    - auth.provider_foundation.local_user_identity_mapping
  given:
    - A local user already exists.
  when:
    - The system records a provider identity for that user.
  then:
    - Future provider lookups can resolve the same local user through the provider plus host plus subject tuple.

- id: auth.provider_foundation.scenario.provider_config
  covers:
    - auth.provider_foundation.provider_catalog
    - auth.provider_foundation.provider_login_configuration
  given:
    - An operator needs to prepare hosted provider login.
  when:
    - The operator saves provider-host configuration for an approved source provider.
  then:
    - The system persists provider-neutral login settings without storing automation credentials in the same record.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/accounts/user_identity.ex
  covers:
    - auth.provider_foundation.local_user_identity_mapping
    - auth.provider_foundation.provider_catalog

- kind: source_file
  target: lib/jido_code/auth_providers.ex
  covers:
    - auth.provider_foundation.provider_login_configuration

- kind: source_file
  target: lib/jido_code/auth_providers/provider_config.ex
  covers:
    - auth.provider_foundation.provider_catalog
    - auth.provider_foundation.provider_login_configuration

- kind: source_file
  target: test/jido_code/accounts/user_identity_test.exs
  covers:
    - auth.provider_foundation.local_user_identity_mapping

- kind: source_file
  target: test/jido_code/auth_providers/provider_config_test.exs
  covers:
    - auth.provider_foundation.provider_catalog
    - auth.provider_foundation.provider_login_configuration
```
