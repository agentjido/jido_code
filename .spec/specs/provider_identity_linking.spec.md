# Provider Identity Linking

This subject defines how provider-backed authentication resolves back to the local user system after provider login policy allows the identity to proceed. It is part of the repo-local foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

```spec-meta
id: auth.provider_identity_linking
kind: feature
status: active
summary: jido_code resolves provider identities to local users by reusing an existing identity, linking verified email addresses, or provisioning a new local user when needed.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/accounts/provider_identity_linker.ex
  - lib/jido_code/accounts/user.ex
  - lib/jido_code/accounts/user_identity.ex
  - test/jido_code/accounts/provider_identity_linker_test.exs
```

## Requirements

```spec-requirements
- id: auth.provider_identity_linking.existing_identity_reuse
  statement: When a provider plus host plus subject identity already exists, the system shall reuse that linked local user instead of creating a second local account.
  priority: must
  stability: stable

- id: auth.provider_identity_linking.verified_email_link
  statement: When no provider identity exists but the provider email is verified and matches an existing local user, the system shall attach the provider identity to that local user.
  priority: must
  stability: stable

- id: auth.provider_identity_linking.auto_create_local_user
  statement: When no linked identity exists and no existing local user matches by verified provider email, the system shall provision a local user record from provider identity data.
  priority: must
  stability: stable

- id: auth.provider_identity_linking.auth_timestamps
  statement: Provider-linked identity records shall store the first and most recent successful provider authentication timestamps.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: auth.provider_identity_linking.scenario.identity_reuse
  covers:
    - auth.provider_identity_linking.existing_identity_reuse
    - auth.provider_identity_linking.auth_timestamps
  given:
    - A provider identity is already linked to a local user.
  when:
    - The same provider identity authenticates again.
  then:
    - The same local user is returned and the most recent authentication timestamp is refreshed without losing the original first-authenticated timestamp.

- id: auth.provider_identity_linking.scenario.verified_email_attach
  covers:
    - auth.provider_identity_linking.verified_email_link
  given:
    - A local user exists without a provider identity.
  when:
    - A provider identity with the same verified email authenticates.
  then:
    - The provider identity attaches to that local user instead of creating a duplicate user.

- id: auth.provider_identity_linking.scenario.auto_create
  covers:
    - auth.provider_identity_linking.auto_create_local_user
    - auth.provider_identity_linking.verified_email_link
  given:
    - No linked provider identity exists and the verified provider email is not yet present in the local directory.
  when:
    - The provider identity authenticates.
  then:
    - The system provisions one local user and future verified identities for the same email attach back to that user.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/accounts/provider_identity_linker.ex
  covers:
    - auth.provider_identity_linking.existing_identity_reuse
    - auth.provider_identity_linking.verified_email_link
    - auth.provider_identity_linking.auto_create_local_user
    - auth.provider_identity_linking.auth_timestamps

- kind: source_file
  target: lib/jido_code/accounts/user.ex
  covers:
    - auth.provider_identity_linking.auto_create_local_user

- kind: source_file
  target: lib/jido_code/accounts/user_identity.ex
  covers:
    - auth.provider_identity_linking.auth_timestamps

- kind: source_file
  target: test/jido_code/accounts/provider_identity_linker_test.exs
  covers:
    - auth.provider_identity_linking.existing_identity_reuse
    - auth.provider_identity_linking.verified_email_link
    - auth.provider_identity_linking.auto_create_local_user
    - auth.provider_identity_linking.auth_timestamps
```
