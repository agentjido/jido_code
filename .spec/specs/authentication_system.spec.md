# Authentication System

This subject defines the baseline local authentication capabilities for `jido_code`. These local flows remain the durable fallback even as linked external provider identities can later provision or attach to the same local users.

```spec-meta
id: auth.system
kind: feature
status: active
summary: jido_code authenticates local users with email-backed identities, first-run password bootstrap, password and magic-link sign-in, confirmation tracking, revocable session credentials backed by persisted security-token surfaces, and ready-state auth handoff that defaults authenticated product entry to dashboard while incomplete onboarding still routes to setup.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/accounts/user.ex
  - lib/jido_code/accounts/token.ex
  - lib/jido_code/accounts/security_tokens.ex
  - lib/jido_code_web/controllers/auth_controller.ex
  - lib/jido_code_web/live_user_auth.ex
  - test/support/conn_case.ex
  - test/jido_code_web/live/auth_session_live_test.exs
  - test/jido_code_web/live/auth_boundary_live_test.exs
  - test/jido_code_web/live/auth_sign_out_live_test.exs
  - test/jido_code_web/live/phase_fifty_eight_integration_test.exs
```

## Requirements

```spec-requirements
- id: auth.system.local_email_identity
  statement: Authentication shall be anchored to a local user record with a unique email identity.
  priority: must
  stability: stable

- id: auth.system.password_registration_and_sign_in
  statement: Local authentication shall support first-run bootstrap-admin creation and later email-and-password sign-in with password confirmation and minimum-length validation.
  priority: must
  stability: stable

- id: auth.system.password_reset
  statement: Local authentication shall support forgot-password recovery by issuing a reset token and allowing token-based password reset.
  priority: must
  stability: stable

- id: auth.system.magic_link
  statement: Local authentication shall support email magic-link sign-in for existing local users.
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

- id: auth.system.ready_state_local_auth_handoff
  statement: Ready-state local authentication shall enter the authenticated product at `/dashboard` by default, preserve explicit `return_to` overrides, and continue to route incomplete onboarding into `/setup` instead of dashboard.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: auth.system.scenario.password_sign_in
  covers:
    - auth.system.password_registration_and_sign_in
    - auth.system.revocable_credentials
    - auth.system.ready_state_local_auth_handoff
  given:
    - A user has a local email identity and a valid password.
  when:
    - The user signs in through the password flow.
  then:
    - The system issues a revocable authenticated session token.
    - Ready-state sign-in enters dashboard unless an explicit product return path is already in force.

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
    - The system signs in the existing local user without reopening public self-registration.
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
  target: lib/jido_code_web/controllers/auth_controller.ex
  covers:
    - auth.system.ready_state_local_auth_handoff

- kind: source_file
  target: lib/jido_code_web/live_user_auth.ex
  covers:
    - auth.system.ready_state_local_auth_handoff

- kind: source_file
  target: test/support/conn_case.ex
  covers:
    - auth.system.local_email_identity
    - auth.system.password_registration_and_sign_in

- kind: source_file
  target: test/jido_code_web/live/auth_session_live_test.exs
  covers:
    - auth.system.local_email_identity
    - auth.system.password_registration_and_sign_in
    - auth.system.ready_state_local_auth_handoff

- kind: source_file
  target: test/jido_code_web/live/auth_boundary_live_test.exs
  covers:
    - auth.system.revocable_credentials

- kind: source_file
  target: test/jido_code_web/live/auth_sign_out_live_test.exs
  covers:
    - auth.system.revocable_credentials

- kind: source_file
  target: test/jido_code_web/live/phase_fifty_eight_integration_test.exs
  covers:
    - auth.system.ready_state_local_auth_handoff
```
