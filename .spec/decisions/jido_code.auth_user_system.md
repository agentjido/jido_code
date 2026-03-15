---
id: jido_code.auth_user_system
status: accepted
date: 2026-03-15
affects:
  - package.jido_code
  - auth.system
  - auth.provider_foundation
  - auth.provider_broker_handoff
  - auth.provider_identity_linking
  - auth.provider_login_policy
  - auth.github_service_credentials
  - users.admin_system
  - auth.github_integration
---

# Local User System With Bootstrap Admin

## Context

`jido_code` already contains local email/password and magic-link authentication, token storage, owner bootstrap, and GitHub integration readiness checks. The product surface has been trimmed to a spec-led baseline, and the next implementation phase needs a stable account model that can grow from the current single-owner setup into a multi-user product.

At the same time, GitHub integration matters for repository automation, but it should not displace the product's own user and authorization model.

## Decision

`jido_code` will treat local user records as the source of truth for product identity and authorization.

The first setup account is the bootstrap administrator. After bootstrap, production registration stays gated and future account creation becomes an administrator-managed workflow rather than open self-service sign-up.

The baseline authentication system will continue to center on email-backed identities with password sign-in, forgot-password recovery, email confirmation, and magic-link access. External provider login, when introduced, will be modeled as provider-specific identities linked back to the same local user system. Matching verified provider email addresses may attach to an existing local user, and otherwise the provider flow may provision a new local user that still lives inside the same directory. Provider-host login policy and allowlists must be evaluated before any provider identity is allowed to create or link a local user. GitHub App and PAT capabilities remain integration mechanisms for repository access, and any future GitHub-backed sign-in must resolve to a local user account before product authorization is evaluated. Broker-managed login configuration and deployment-local GitHub automation credentials remain separate concerns, and broker-issued handoff tokens must be validated against deployment-signed state before local account linking begins.

## Consequences

- Authentication work should extend the existing `Accounts.User` model instead of introducing a parallel owner-only identity model.
- Provider-backed login should add linked identity records and provider configuration rather than replacing the local user table.
- Provider-backed login should reuse an existing linked identity first, otherwise link by verified email or create a local user without creating a second authorization system.
- Provider-backed login should fail closed when the provider-host login policy or allowlist does not authorize the identity.
- Provider-backed login should fail closed when broker handoff issuer, audience, expiry, nonce binding, or nonce replay validation does not pass.
- Admin identification and user provisioning become first-class product concerns.
- GitHub integration can evolve independently without blocking local authentication.
- GitHub automation secrets should be named and managed as deployment-local credentials rather than as provider-login broker settings.
- Specs for authentication, provider auth, provider identity linking, provider login policy, user administration, and GitHub-backed identity should stay aligned with this decision as implementation progresses.
