# Authentication System

This subject defines the baseline local authentication capabilities for `jido_code`. These local flows remain the durable fallback even as linked external provider identities are introduced separately.

```spec-meta
id: auth.system
kind: feature
status: active
summary: jido_code authenticates local users with email-backed identities, password and magic-link flows, confirmation, and revocable session credentials.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/accounts/user.ex
  - lib/jido_code/accounts/token.ex
  - lib/jido_code/accounts/security_tokens.ex
  - test/jido_code_web/live/auth_sign_out_live_test.exs
```

## Requirements

```spec-requirements
- id: auth.system.local_email_identity
  statement: Authentication shall be anchored to a local user record with a unique email identity.
  priority: must
  stability: stable

- id: auth.system.password_registration_and_sign_in
  statement: Local authentication shall support email-and-password registration and sign-in with password confirmation and minimum-length validation.
  priority: must
  stability: stable

- id: auth.system.password_reset
  statement: Local authentication shall support forgot-password recovery by issuing a reset token and allowing token-based password reset.
  priority: must
  stability: stable

- id: auth.system.magic_link
  statement: Local authentication shall support email magic-link sign-in and registration.
  priority: must
  stability: stable

- id: auth.system.email_confirmation
  statement: New email-backed identities shall support confirmation tracking before they are treated as confirmed accounts.
  priority: must
  stability: stable

- id: auth.system.revocable_credentials
  statement: The system shall persist session credentials and API keys so they can be listed and revoked as part of account security operations.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: auth.system.scenario.password_sign_in
  covers:
    - auth.system.password_registration_and_sign_in
    - auth.system.revocable_credentials
  given:
    - A user has a local email identity and a valid password.
  when:
    - The user signs in through the password flow.
  then:
    - The system issues a revocable authenticated session token.

- id: auth.system.scenario.password_reset
  covers:
    - auth.system.password_reset
  given:
    - A user has forgotten their password.
  when:
    - The user requests reset instructions and completes the reset flow with a valid token.
  then:
    - The password is changed and the user can authenticate with the new secret.

- id: auth.system.scenario.magic_link
  covers:
    - auth.system.magic_link
    - auth.system.local_email_identity
  given:
    - A user prefers passwordless access.
  when:
    - The user requests and consumes a valid magic link.
  then:
    - The system signs in the existing user or creates the local user identity allowed by policy.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/accounts/user.ex
  covers:
    - auth.system.local_email_identity
    - auth.system.password_registration_and_sign_in
    - auth.system.password_reset
    - auth.system.magic_link
    - auth.system.email_confirmation

- kind: source_file
  target: lib/jido_code/accounts/token.ex
  covers:
    - auth.system.revocable_credentials

- kind: source_file
  target: lib/jido_code/accounts/security_tokens.ex
  covers:
    - auth.system.revocable_credentials

- kind: source_file
  target: test/jido_code_web/live/auth_sign_out_live_test.exs
  covers:
    - auth.system.revocable_credentials
```
