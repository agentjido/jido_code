# Provider Login Policy

This subject defines how provider login enablement and allowlists are evaluated before any local user linking work occurs. It is part of the repo-local foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

```spec-meta
id: auth.provider_login_policy
kind: feature
status: active
summary: jido_code evaluates provider login enablement and provider-neutral allowlists before allowing provider identities to resolve into local users, and blocked identities never fall through to any public registration path.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/auth_providers/login_policy.ex
  - lib/jido_code/accounts/provider_identity_linker.ex
  - test/jido_code/auth_providers/login_policy_test.exs
  - test/jido_code/accounts/provider_identity_linker_test.exs
```

## Requirements

```spec-requirements
- id: auth.provider_login_policy.provider_enablement
  statement: Provider login shall respect per-provider and per-host enablement flags before allowing login resolution.
  priority: must
  stability: stable

- id: auth.provider_login_policy.allowlist_evaluation
  statement: Provider login shall evaluate the configured allowlist mode and values before local user linking proceeds.
  priority: must
  stability: stable

- id: auth.provider_login_policy.provider_neutral_logic
  statement: Allowlist evaluation shall remain provider-neutral so users, organizations, teams, groups, and workspaces can be evaluated through the same policy contract.
  priority: must
  stability: stable

- id: auth.provider_login_policy.blocked_before_linking
  statement: Provider identities that fail login policy shall be rejected before the system creates or links a local user, including any internal provisioning path used by provider auth.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: auth.provider_login_policy.scenario.disabled_provider
  covers:
    - auth.provider_login_policy.provider_enablement
  given:
    - A provider host is configured but login is disabled.
  when:
    - A provider identity attempts login.
  then:
    - The login is rejected before local user linking begins.

- id: auth.provider_login_policy.scenario.allowlist_pass
  covers:
    - auth.provider_login_policy.allowlist_evaluation
    - auth.provider_login_policy.provider_neutral_logic
  given:
    - A provider host is configured with an allowlist.
  when:
    - Provider identity facts match the configured allowlist values.
  then:
    - The login is allowed to proceed into local identity linking.

- id: auth.provider_login_policy.scenario.allowlist_block
  covers:
    - auth.provider_login_policy.blocked_before_linking
  given:
    - A provider identity does not satisfy the configured allowlist.
  when:
    - Login is attempted.
  then:
    - The identity is rejected before a local user is created or linked.
    - The rejection does not fall through to public registration or any later provider-provisioning step.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/auth_providers/login_policy.ex
  covers:
    - auth.provider_login_policy.provider_enablement
    - auth.provider_login_policy.allowlist_evaluation
    - auth.provider_login_policy.provider_neutral_logic

- kind: source_file
  target: lib/jido_code/accounts/provider_identity_linker.ex
  covers:
    - auth.provider_login_policy.blocked_before_linking

- kind: source_file
  target: test/jido_code/auth_providers/login_policy_test.exs
  covers:
    - auth.provider_login_policy.provider_enablement
    - auth.provider_login_policy.allowlist_evaluation
    - auth.provider_login_policy.provider_neutral_logic

- kind: source_file
  target: test/jido_code/accounts/provider_identity_linker_test.exs
  covers:
    - auth.provider_login_policy.blocked_before_linking
```
