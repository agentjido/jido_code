# Provider Login Flow

This subject defines the first broker-backed provider login path that is live in `jido_code`. It is part of the repo-local auth-provider foundation captured by `package.jido_code.auth_provider_foundation_in_repo`. The initial implementation is GitHub-first, but the session-issuance service remains provider-neutral so future GitLab and Bitbucket login can reuse the same local-user and token model.

```spec-meta
id: auth.provider_login_flow
kind: feature
status: active
summary: jido_code exposes a GitHub provider sign-in entrypoint, consumes broker-validated provider claims, links them to the local user system, and issues the same revocable local session tokens used by email sign-in.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/auth_providers/provider_login.ex
  - lib/jido_code_web/controllers/provider_auth_controller.ex
  - lib/jido_code_web/live/home_live.ex
  - test/jido_code/auth_providers/provider_login_test.exs
  - test/jido_code_web/controllers/provider_auth_controller_test.exs
  - test/jido_code_web/live/home_live_test.exs
```

## Requirements

```spec-requirements
- id: auth.provider_login_flow.entrypoint_visible
  statement: The landing page shall expose a GitHub provider sign-in entrypoint when GitHub.com provider login is enabled.
  priority: must
  stability: evolving

- id: auth.provider_login_flow.local_auth_fallback_visible
  statement: Local email sign-in and account-creation entrypoints shall remain visible even when provider login is unavailable or disabled.
  priority: must
  stability: stable

- id: auth.provider_login_flow.broker_handoff_consumption
  statement: Provider sign-in shall consume broker-validated provider claims only after the deployment-side state and broker handoff contract has already been validated.
  priority: must
  stability: stable

- id: auth.provider_login_flow.local_user_resolution
  statement: Successful provider sign-in shall resolve to the existing local user model through provider-identity linking before a browser session is issued.
  priority: must
  stability: stable

- id: auth.provider_login_flow.local_session_issuance
  statement: Successful provider sign-in shall issue the same revocable local browser session credential used by local authentication.
  priority: must
  stability: stable

- id: auth.provider_login_flow.redirect_path_completion
  statement: After successful provider sign-in, the browser shall redirect to the signed deployment redirect path rather than stopping at an intermediate contract response.
  priority: must
  stability: evolving

- id: auth.provider_login_flow.provider_neutral_session_service
  statement: The local session-issuance service for provider sign-in shall remain provider-neutral so additional VCS identity providers can reuse the same token and local-user model.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: auth.provider_login_flow.scenario.github_entrypoint
  covers:
    - auth.provider_login_flow.entrypoint_visible
    - auth.provider_login_flow.local_auth_fallback_visible
  given:
    - GitHub.com provider login has been enabled for the deployment.
  when:
    - An anonymous visitor opens the landing page.
  then:
    - The page shows both local auth entrypoints and the GitHub sign-in entrypoint.

- id: auth.provider_login_flow.scenario.github_sign_in
  covers:
    - auth.provider_login_flow.broker_handoff_consumption
    - auth.provider_login_flow.local_user_resolution
    - auth.provider_login_flow.local_session_issuance
    - auth.provider_login_flow.redirect_path_completion
  given:
    - The deployment has already validated broker state and handoff claims for a GitHub identity.
  when:
    - The provider sign-in service consumes those claims.
  then:
    - The flow links or provisions the local user, issues a revocable session token, and redirects the browser to the signed redirect path.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/auth_providers/provider_login.ex
  covers:
    - auth.provider_login_flow.local_user_resolution
    - auth.provider_login_flow.local_session_issuance
    - auth.provider_login_flow.provider_neutral_session_service

- kind: source_file
  target: lib/jido_code_web/controllers/provider_auth_controller.ex
  covers:
    - auth.provider_login_flow.broker_handoff_consumption
    - auth.provider_login_flow.local_session_issuance
    - auth.provider_login_flow.redirect_path_completion

- kind: source_file
  target: lib/jido_code_web/live/home_live.ex
  covers:
    - auth.provider_login_flow.entrypoint_visible
    - auth.provider_login_flow.local_auth_fallback_visible

- kind: source_file
  target: test/jido_code/auth_providers/provider_login_test.exs
  covers:
    - auth.provider_login_flow.local_user_resolution
    - auth.provider_login_flow.local_session_issuance
    - auth.provider_login_flow.provider_neutral_session_service

- kind: source_file
  target: test/jido_code_web/controllers/provider_auth_controller_test.exs
  covers:
    - auth.provider_login_flow.broker_handoff_consumption
    - auth.provider_login_flow.local_session_issuance
    - auth.provider_login_flow.redirect_path_completion

- kind: source_file
  target: test/jido_code_web/live/home_live_test.exs
  covers:
    - auth.provider_login_flow.entrypoint_visible
    - auth.provider_login_flow.local_auth_fallback_visible
```
