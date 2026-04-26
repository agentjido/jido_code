# User Administration

<!-- current_truth.reconciled_with_branch: bootstrap-admin creation and entry into the signed-in setup start surface remain current truth here, while setup now describes runtime defaults as seed metadata for later repo import instead of a permanent topology rule, ready-state local auth now defaults to dashboard instead of reopening `/welcome`, signed-in `/welcome` stays a compact dashboard/settings handoff rather than a second operator console, later GitHub PAT plus multi-repository GitHub import follow-up still depend on setup-owned server gating, group linked repositories by account origin with the account name visible on each card, and do not keep completed imports selected as a new bootstrap gate, and durable provider-login or Git integration management now has a settings-owned `/settings/auth` destination instead of relying on welcome-page operator controls. -->

This subject defines the target user-management model for `jido_code` as it evolves from owner bootstrap toward a durable admin-managed account system. Local users remain the shared directory even when a user later gains linked external identities or is first provisioned from a provider login.

<!-- covers: setup.onboarding.admin_bootstrap_completion_gate -->

```spec-meta
id: users.admin_system
kind: feature
status: active
summary: jido_code boots through a `/welcome` first-run gate that creates or confirms one bootstrap administrator, then hands the signed-in admin to a lightweight `/setup` start surface whose runtime-default copy and follow-up work stay non-blocking before growing into an admin-managed multi-user account system with guarded registration, with later ready-state auth entering dashboard and durable provider or Git integration management living under `/settings/auth`.
decisions:
  - jido_code.auth_user_system
  - jido_code.welcome_bootstrap_entry_with_dashboard_and_settings_handoff
surface:
  - lib/jido_code/setup/bootstrap_status.ex
  - lib/jido_code/setup/owner_bootstrap.ex
  - lib/jido_code/setup/owner_recovery.ex
  - lib/jido_code/accounts/user.ex
  - lib/jido_code/accounts/checks/registration_allowed.ex
  - lib/jido_code_web/live/home_live.ex
  - test/support/conn_case.ex
  - priv/repo/migrations/20260325220016_migrate_resources1_dev.exs
  - priv/resource_snapshots/repo/users/20260325220016_dev.json
  - test/jido_code_web/live/phase_sixty_integration_test.exs
  - test/jido_code_web/live/phase_sixty_three_integration_test.exs
  - test/jido_code_web/live/setup_live_test.exs
```

## Requirements

```spec-requirements
- id: users.admin_system.bootstrap_admin
  statement: Initial setup shall use the `/welcome` first-run flow to create or confirm exactly one bootstrap administrator, auto-confirm that account, mark it as an administrator, and treat that signed-in bootstrap outcome as the only hard first-run account gate before optional product setup is deferred into a signed-in start surface.
  priority: must
  stability: stable

- id: users.admin_system.local_user_directory
  statement: The account model shall treat administrators and standard members as users in one local user system rather than separate identity silos.
  priority: must
  stability: stable

- id: users.admin_system.admin_role_assignment
  statement: The system shall identify which users are administrators so policy, auditing, and management actions can resolve the acting admin explicitly.
  priority: must
  stability: stable

- id: users.admin_system.admin_managed_provisioning
  statement: Administrators shall be able to add users and initiate account creation without reopening unrestricted public registration.
  priority: must
  stability: stable

- id: users.admin_system.self_service_auth_lifecycle
  statement: Both administrators and standard users shall be able to sign in, sign out, and complete forgot-password recovery for their own accounts.
  priority: must
  stability: stable

- id: users.admin_system.registration_guardrails
  statement: Once the bootstrap administrator exists, open self-registration shall remain gated unless an administrator explicitly provisions or invites the account.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: users.admin_system.scenario.bootstrap_admin
  covers:
    - users.admin_system.bootstrap_admin
    - users.admin_system.local_user_directory
  given:
    - The deployment has no existing users.
  when:
    - The operator completes first-run bootstrap from `/welcome`.
  then:
    - The system establishes one bootstrap administrator who becomes the first accountable local user and signs that administrator into the product, while optional repo and integration setup continues as signed-in follow-up work.
    - The signed-in admin is not blocked on provider, GitHub, or project setup before entering the product.

- id: users.admin_system.scenario.admin_adds_user
  covers:
    - users.admin_system.admin_managed_provisioning
    - users.admin_system.admin_role_assignment
    - users.admin_system.registration_guardrails
  given:
    - A bootstrap administrator is signed in.
  when:
    - The administrator provisions a new team member account.
  then:
    - The new account enters the local user system without reopening unrestricted public sign-up.

- id: users.admin_system.scenario.standard_user_recovers_access
  covers:
    - users.admin_system.self_service_auth_lifecycle
  given:
    - A standard user account exists in the local directory.
  when:
    - The user forgets their password.
  then:
    - The user completes self-service recovery without requiring direct administrator password handling.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/setup/bootstrap_status.ex
  covers:
    - users.admin_system.bootstrap_admin
    - users.admin_system.registration_guardrails

- kind: source_file
  target: lib/jido_code/setup/owner_bootstrap.ex
  covers:
    - users.admin_system.bootstrap_admin

- kind: source_file
  target: lib/jido_code/setup/owner_recovery.ex
  covers:
    - users.admin_system.bootstrap_admin
    - users.admin_system.admin_role_assignment

- kind: source_file
  target: lib/jido_code/accounts/user.ex
  covers:
    - users.admin_system.local_user_directory
    - users.admin_system.admin_role_assignment
    - users.admin_system.admin_managed_provisioning
    - users.admin_system.self_service_auth_lifecycle

- kind: source_file
  target: lib/jido_code/accounts/checks/registration_allowed.ex
  covers:
    - users.admin_system.registration_guardrails
    - users.admin_system.admin_managed_provisioning

- kind: source_file
  target: lib/jido_code_web/live/home_live.ex
  covers:
    - users.admin_system.bootstrap_admin
    - users.admin_system.registration_guardrails

- kind: source_file
  target: test/support/conn_case.ex
  covers:
    - users.admin_system.bootstrap_admin
    - users.admin_system.self_service_auth_lifecycle

- kind: source_file
  target: test/jido_code_web/live/setup_live_test.exs
  covers:
    - users.admin_system.bootstrap_admin
    - users.admin_system.admin_role_assignment
    - users.admin_system.registration_guardrails

- kind: source_file
  target: test/jido_code_web/live/phase_sixty_integration_test.exs
  covers:
    - users.admin_system.bootstrap_admin
```
