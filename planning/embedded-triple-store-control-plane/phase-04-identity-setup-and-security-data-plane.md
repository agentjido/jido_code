# Phase 4 - Identity, Setup, And Security Data Plane

Back to plan: [README](./README.md)

**Description:** This phase moves bootstrap state, local identity, provider identity links, tokens, API keys, provider configuration, and secret references onto the product store. It deliberately avoids retaining Ash Authentication or Postgres-backed token tables.

- [ ] 4 Phase - Identity, setup, and security data plane.

  Description: Replace identity and setup persistence first because these flows define how operators gain access to the rest of the product.

## 4.1 Section - Setup And System Config

**Description:** This section makes onboarding and runtime defaults read from the embedded control-plane store.

- [x] 4.1 Section - Setup and system config.

  Description: System config becomes a singleton semantic record with explicit reset and bootstrap semantics.

  - [x] 4.1.1 Task - Replace `SystemConfigRecord` persistence.

    Description: Setup state should be stored through the new product store, not Ash resources or Ecto.

    - [x] 4.1.1.1 Subtask - Implement system config codec and singleton identity.
    - [x] 4.1.1.2 Subtask - Rewire `SystemConfigPersistence` to the store behaviour.
    - [x] 4.1.1.3 Subtask - Preserve test-mode in-memory config overrides where tests need isolation.

  - [x] 4.1.2 Task - Replace setup bootstrap reads and writes.

    Description: Owner bootstrap, onboarding reset, and readiness checks must use product services.

    - [x] 4.1.2.1 Subtask - Rewire owner bootstrap user lookup and creation calls.
    - [x] 4.1.2.2 Subtask - Rewire onboarding reset to delete or reset store-backed setup records.
    - [x] 4.1.2.3 Subtask - Rewire bootstrap status and prerequisite checks away from Ash reads.

## 4.2 Section - Local Users And Provider Identities

**Description:** This section replaces Ash Authentication resource state with explicit identity records and auth services.

- [x] 4.2 Section - Local users and provider identities.

  Description: Local users, provider identities, and registration policy become product records with hand-authored auth logic.

  - [x] 4.2.1 Task - Implement user and identity store services.

    Description: User records need canonical identity, email lookup, admin state, confirmation state, and provider links.

    - [x] 4.2.1.1 Subtask - Implement user, user identity, provider config, API key, and token codecs.
    - [x] 4.2.1.2 Subtask - Implement email and provider-subject uniqueness checks.
    - [x] 4.2.1.3 Subtask - Implement user projection helpers for current scope and LiveView sessions.

  - [x] 4.2.2 Task - Replace authentication token flows.

    Description: Password reset, magic link, API key, and session token flows should no longer depend on Ash Authentication tables.

    - [x] 4.2.2.1 Subtask - Implement token creation, lookup, expiration, and revocation through the embedded store.
    - [x] 4.2.2.2 Subtask - Implement API key hashing and revocation without storing plaintext key material.
    - [x] 4.2.2.3 Subtask - Replace Ash Authentication sender and verification entrypoints with product-owned services.

## 4.3 Section - Secret References And Provider Config

**Description:** This section moves secret metadata and provider login policy into semantic records while keeping secret material outside the graph.

- [x] 4.3 Section - Secret references and provider config.

  Description: The graph records references, lifecycle metadata, and audit facts; encrypted or external secret material remains outside semantic triples.

  - [x] 4.3.1 Task - Implement secret reference store services.

    Description: Secret refs need lifecycle state, rotation metadata, audit rows, and safe display projections.

    - [x] 4.3.1.1 Subtask - Implement secret ref and secret lifecycle audit codecs.
    - [x] 4.3.1.2 Subtask - Rewire secret creation, rotation, deletion, and lookup paths.
    - [x] 4.3.1.3 Subtask - Assert encoded triples never include plaintext secret values or encrypted blobs intended for external storage.

  - [x] 4.3.2 Task - Implement provider configuration services.

    Description: Provider login settings, host scoping, and registration policy should be controlled by store-backed records.

    - [x] 4.3.2.1 Subtask - Rewire provider login policy lookup away from Ash queries.
    - [x] 4.3.2.2 Subtask - Rewire GitHub service credential lookup to secret references and provider config projections.
    - [x] 4.3.2.3 Subtask - Preserve setup fallback behavior when provider config is missing or incomplete.

## 4.4 Section - Integration Tests

**Description:** This final section proves setup, identity, auth, and security flows work without Ash/Postgres.

- [ ] 4.4 Section - Integration tests.

  Description: Exercise user-visible and security-sensitive flows end to end against the embedded store.

  - [ ] 4.4.1 Task - Add setup and identity integration coverage.

    Description: Setup tests should prove a fresh store can bootstrap and sign in an owner.

    - [ ] 4.4.1.1 Subtask - Run owner bootstrap from an empty embedded store.
    - [ ] 4.4.1.2 Subtask - Sign in with password, magic link, and provider identity where currently supported.
    - [ ] 4.4.1.3 Subtask - Prove onboarding reset clears setup and identity state as intended.

  - [ ] 4.4.2 Task - Add security integration coverage.

    Description: Security tests should prove secret metadata is queryable while secret material is not projected.

    - [ ] 4.4.2.1 Subtask - Create, rotate, and delete a secret reference with audit events.
    - [ ] 4.4.2.2 Subtask - Query provider config and secret refs through product services.
    - [ ] 4.4.2.3 Subtask - Scan written quads for forbidden plaintext secret fields.
