# Provider Broker Handoff

This subject defines the deployment-side contract for broker-issued provider login handoffs. It is part of the repo-local foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

```spec-meta
id: auth.provider_broker_handoff
kind: feature
status: active
summary: jido_code signs deployment-owned provider state, validates broker JWT handoffs with issuer and audience trust, blocks nonce replay with a consistent request clock, and enforces the contract that must pass before provider-specific local sign-in can proceed.
decisions:
  - jido_code.auth_user_system
surface:
  - lib/jido_code/auth_providers/broker_state.ex
  - lib/jido_code/auth_providers/broker_nonce_store.ex
  - lib/jido_code/auth_providers/broker_handoff.ex
  - lib/jido_code_web/controllers/provider_auth_controller.ex
  - test/jido_code/auth_providers/broker_state_test.exs
  - test/jido_code/auth_providers/broker_handoff_test.exs
  - test/jido_code_web/controllers/provider_auth_controller_test.exs
```

## Requirements

```spec-requirements
- id: auth.provider_broker_handoff.state_token_signature
  statement: The deployment shall issue a signed provider-auth state token that binds provider, provider host, broker base URL, redirect path, and nonce.
  priority: must
  stability: stable

- id: auth.provider_broker_handoff.state_token_ttl
  statement: Signed provider-auth state shall expire after a bounded TTL and fail closed when reused after expiry.
  priority: must
  stability: stable

- id: auth.provider_broker_handoff.broker_jwt_validation
  statement: Broker-issued handoff JWTs shall be verified against broker JWKS material before any local identity linking or session issuance is attempted.
  priority: must
  stability: stable

- id: auth.provider_broker_handoff.issuer_and_audience_validation
  statement: Broker-issued handoff JWTs shall fail closed when issuer or audience does not match the provider-host configuration.
  priority: must
  stability: stable

- id: auth.provider_broker_handoff.nonce_binding
  statement: Broker-issued handoff JWTs shall bind back to the signed deployment state through a matching nonce and provider context.
  priority: must
  stability: stable

- id: auth.provider_broker_handoff.nonce_replay_protection
  statement: Successfully validated broker handoff nonces shall be single-use so replay attempts fail closed and expiry evaluation stays consistent with the validating request clock.
  priority: must
  stability: stable

- id: auth.provider_broker_handoff.start_endpoint_contract
  statement: The deployment start endpoint shall redirect to the configured broker start URL with signed state, provider host, and deployment callback URL.
  priority: must
  stability: evolving

- id: auth.provider_broker_handoff.complete_endpoint_contract
  statement: The deployment complete endpoint shall validate signed state and broker handoff JWT before provider-specific identity linking and local session issuance are allowed to proceed.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: auth.provider_broker_handoff.scenario.state_round_trip
  covers:
    - auth.provider_broker_handoff.state_token_signature
    - auth.provider_broker_handoff.state_token_ttl
  given:
    - A deployment operator starts provider sign-in for a configured provider host.
  when:
    - The deployment issues and later verifies the provider-auth state token.
  then:
    - The provider state round-trips with the same nonce and fails once it expires.

- id: auth.provider_broker_handoff.scenario.handoff_validation
  covers:
    - auth.provider_broker_handoff.broker_jwt_validation
    - auth.provider_broker_handoff.issuer_and_audience_validation
    - auth.provider_broker_handoff.nonce_binding
    - auth.provider_broker_handoff.nonce_replay_protection
  given:
    - A broker returns a signed handoff JWT.
  when:
    - The deployment validates that JWT against broker trust settings and the signed state nonce.
  then:
    - Invalid issuer, audience, expiry, or replay attempts fail closed.

- id: auth.provider_broker_handoff.scenario.endpoint_contract
  covers:
    - auth.provider_broker_handoff.start_endpoint_contract
    - auth.provider_broker_handoff.complete_endpoint_contract
  given:
    - A provider-host config has broker trust fields.
  when:
    - The deployment start and complete endpoints are invoked.
  then:
    - Start redirects to the broker contract URL, and complete validates the broker contract before any local provider sign-in work runs.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/auth_providers/broker_state.ex
  covers:
    - auth.provider_broker_handoff.state_token_signature
    - auth.provider_broker_handoff.state_token_ttl
    - auth.provider_broker_handoff.nonce_binding

- kind: source_file
  target: lib/jido_code/auth_providers/broker_nonce_store.ex
  covers:
    - auth.provider_broker_handoff.nonce_replay_protection

- kind: source_file
  target: lib/jido_code/auth_providers/broker_handoff.ex
  covers:
    - auth.provider_broker_handoff.broker_jwt_validation
    - auth.provider_broker_handoff.issuer_and_audience_validation
    - auth.provider_broker_handoff.nonce_binding
    - auth.provider_broker_handoff.nonce_replay_protection

- kind: source_file
  target: lib/jido_code_web/controllers/provider_auth_controller.ex
  covers:
    - auth.provider_broker_handoff.start_endpoint_contract
    - auth.provider_broker_handoff.complete_endpoint_contract

- kind: source_file
  target: test/jido_code/auth_providers/broker_state_test.exs
  covers:
    - auth.provider_broker_handoff.state_token_signature
    - auth.provider_broker_handoff.state_token_ttl

- kind: source_file
  target: test/jido_code/auth_providers/broker_handoff_test.exs
  covers:
    - auth.provider_broker_handoff.broker_jwt_validation
    - auth.provider_broker_handoff.issuer_and_audience_validation
    - auth.provider_broker_handoff.nonce_binding
    - auth.provider_broker_handoff.nonce_replay_protection

- kind: source_file
  target: test/jido_code_web/controllers/provider_auth_controller_test.exs
  covers:
    - auth.provider_broker_handoff.start_endpoint_contract
    - auth.provider_broker_handoff.complete_endpoint_contract
```
