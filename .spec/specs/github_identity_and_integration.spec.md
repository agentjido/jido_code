# GitHub Identity And Integration

<!-- current_truth.reconciled_with_branch: setup GitHub repository follow-up and auth-mode verification remain governed by this subject. -->

This subject defines how GitHub-backed access should relate to the local user system and setup-time repository integration checks, including future local-user resolution through provider identity linking.

<!-- covers: setup.onboarding.deferred_integrations -->

```spec-meta
id: auth.github_integration
kind: feature
status: active
summary: jido_code keeps local user accounts as the source of truth while supporting GitHub App and PAT integration, synchronizing installation readiness, and preparing for optional GitHub-backed sign-in.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/setup/github_credential_checks.ex
  - lib/jido_code/setup/github_installation_sync.ex
  - lib/jido_code/accounts/user.ex
  - lib/jido_code/accounts/user_identity.ex
  - test/support/conn_case.ex
  - test/jido_code/setup/github_credential_checks_test.exs
  - test/jido_code_web/live/setup_live_github_auth_mode_test.exs
```

## Requirements

```spec-requirements
- id: auth.github_integration.readiness_feedback
  statement: Signed-in GitHub setup and follow-up product surfaces shall report whether GitHub App mode or PAT fallback is configured and whether repository access is confirmed for the current administrator context.
  priority: must
  stability: stable

- id: auth.github_integration.github_app_preferred
  statement: When GitHub-backed automation is enabled, GitHub App mode shall be the preferred integration path over PAT fallback because it offers scoped installation access and repository-aware validation.
  priority: must
  stability: stable

- id: auth.github_integration.local_user_mapping
  statement: If GitHub-backed user sign-in is introduced, it shall resolve to a local user record and preserve the same administrator-versus-member role model used by local authentication.
  priority: must
  stability: stable

- id: auth.github_integration.non_blocking_local_auth
  statement: Email/password and magic-link authentication shall remain available even when GitHub App configuration is absent or invalid, and missing GitHub setup shall not block the initial signed-in product entry path.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: auth.github_integration.scenario.github_app_ready
  covers:
    - auth.github_integration.readiness_feedback
    - auth.github_integration.github_app_preferred
  given:
    - GitHub App credentials are configured and the installation can access the expected repositories.
  when:
    - A signed-in follow-up surface validates GitHub integration.
  then:
    - The system reports GitHub App mode as ready for the current administrator context.

- id: auth.github_integration.scenario_pat_fallback
  covers:
    - auth.github_integration.readiness_feedback
    - auth.github_integration.non_blocking_local_auth
  given:
    - GitHub App credentials are not configured and PAT validation succeeds.
  when:
    - A signed-in follow-up surface validates GitHub integration.
  then:
    - The system reports PAT fallback readiness without blocking local user authentication flows.

- id: auth.github_integration.scenario_future_github_sign_in
  covers:
    - auth.github_integration.local_user_mapping
  given:
    - A future GitHub-backed sign-in flow is enabled.
  when:
    - A GitHub identity authenticates successfully.
  then:
    - The system links that identity to a local user record before authorization decisions are made.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/setup/github_credential_checks.ex
  covers:
    - auth.github_integration.readiness_feedback
    - auth.github_integration.github_app_preferred
    - auth.github_integration.non_blocking_local_auth

- kind: source_file
  target: lib/jido_code/setup/github_installation_sync.ex
  covers:
    - auth.github_integration.github_app_preferred

- kind: source_file
  target: lib/jido_code/accounts/user.ex
  covers:
    - auth.github_integration.local_user_mapping

- kind: source_file
  target: lib/jido_code/accounts/user_identity.ex
  covers:
    - auth.github_integration.local_user_mapping

- kind: source_file
  target: test/support/conn_case.ex
  covers:
    - auth.github_integration.non_blocking_local_auth

- kind: source_file
  target: test/jido_code/setup/github_credential_checks_test.exs
  covers:
    - auth.github_integration.readiness_feedback
    - auth.github_integration.non_blocking_local_auth

- kind: source_file
  target: test/jido_code_web/live/setup_live_github_auth_mode_test.exs
  covers:
    - auth.github_integration.non_blocking_local_auth
```
