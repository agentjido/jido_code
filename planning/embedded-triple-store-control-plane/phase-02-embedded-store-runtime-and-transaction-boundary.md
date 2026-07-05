# Phase 2 - Embedded Store Runtime And Transaction Boundary

Back to plan: [README](./README.md)

**Description:** This phase introduces the local embedded `triple_store` runtime as the only product persistence engine. It replaces `JidoCode.Repo` supervision with a product-owned quad-store process, transaction boundary, startup bootstrap, and test sandbox pattern.

- [ ] 2 Phase - Embedded store runtime and transaction boundary.

  Description: Create the runtime substrate that later product services can use without depending on Ash or Ecto.

## 2.1 Section - Store Supervision

**Description:** This section starts and owns the embedded quad store in the application supervision tree.

- [x] 2.1 Section - Store supervision.

  Description: Replace repository supervision with a small, explicit TripleStore supervisor and registry.

  - [x] 2.1.1 Task - Add `JidoCode.ControlPlane.StoreServer`.

    Description: The server opens the embedded store, owns the handle, and centralizes close, health, and restart behavior.

    - [x] 2.1.1.1 Subtask - Open `TripleStore.open(path, schema: :quad)` from configured runtime path.
    - [x] 2.1.1.2 Subtask - Load required ontology graphs at boot or explicit reset.
    - [x] 2.1.1.3 Subtask - Close the store cleanly on termination.

  - [x] 2.1.2 Task - Add configuration and path policy.

    Description: Store location must be deterministic in dev, test, production, and desktop modes.

    - [x] 2.1.2.1 Subtask - Add config keys for control-plane store path, reset policy, and open timeout.
    - [x] 2.1.2.2 Subtask - Keep test stores isolated per test partition or test process.
    - [x] 2.1.2.3 Subtask - Keep repository-local semantic graph stores separate from the product control-plane store.

## 2.2 Section - Transaction And Update Boundary

**Description:** This section defines how writes happen safely without Ash changesets or database transactions.

- [ ] 2.2 Section - Transaction and update boundary.

  Description: Route every mutation through one product-owned command boundary that validates, rewrites, and commits quads atomically enough for product invariants.

  - [ ] 2.2.1 Task - Define write command shape.

    Description: Store callers should submit typed commands, not raw SPARQL update strings.

    - [ ] 2.2.1.1 Subtask - Define insert, replace-subject, delete-subject, append-event, and upsert-by-identity commands.
    - [ ] 2.2.1.2 Subtask - Include actor, correlation id, graph name, expected identity, and validation context in each command.
    - [ ] 2.2.1.3 Subtask - Return typed outcomes with written subject IRIs and event IRIs.

  - [ ] 2.2.2 Task - Implement conflict and optimistic concurrency checks.

    Description: The embedded store must explicitly enforce constraints previously supplied by Ash/Postgres.

    - [ ] 2.2.2.1 Subtask - Implement uniqueness checks using SPARQL reads before writes.
    - [ ] 2.2.2.2 Subtask - Add expected revision or updated-at checks for replace operations.
    - [ ] 2.2.2.3 Subtask - Return deterministic conflict, stale write, and invalid command errors.

## 2.3 Section - Query Boundary

**Description:** This section defines safe query access over product records.

- [ ] 2.3 Section - Query boundary.

  Description: Product callers receive shaped projections from named query helpers, while explicit SPARQL remains a diagnostics and specialist capability.

  - [ ] 2.3.1 Task - Add bounded query APIs.

    Description: Query APIs should be small, typed, and aligned with product use cases.

    - [ ] 2.3.1.1 Subtask - Add get-by-id, list-by-class, list-by-repo, and lookup-by-identity helpers.
    - [ ] 2.3.1.2 Subtask - Add pagination, limit, and timeout options with conservative defaults.
    - [ ] 2.3.1.3 Subtask - Add degraded error shaping for parse errors, missing graph, timeout, and store unavailable cases.

  - [ ] 2.3.2 Task - Add raw SPARQL escape hatch for diagnostics.

    Description: Raw SPARQL must stay explicit, bounded, and unavailable to ordinary UI paths.

    - [ ] 2.3.2.1 Subtask - Route diagnostics queries through a named product action.
    - [ ] 2.3.2.2 Subtask - Enforce graph allow-list, timeout, and row limits.
    - [ ] 2.3.2.3 Subtask - Redact security and auth graph literals from generic diagnostics output.

## 2.4 Section - Integration Tests

**Description:** This final section proves the embedded store runtime can boot, write, query, and reset without Ash/Postgres.

- [ ] 2.4 Section - Integration tests.

  Description: Exercise the store as a supervised product dependency and as an isolated test dependency.

  - [ ] 2.4.1 Task - Add supervised store tests.

    Description: Runtime tests should prove the store starts under application supervision and survives normal lifecycle operations.

    - [ ] 2.4.1.1 Subtask - Start the store with `start_supervised!/1` in tests.
    - [ ] 2.4.1.2 Subtask - Verify ontology bootstrap creates expected named graphs.
    - [ ] 2.4.1.3 Subtask - Verify restart reopens the same embedded store path.

  - [ ] 2.4.2 Task - Add transaction and query tests.

    Description: Store command tests should cover successful writes and constraint failures.

    - [ ] 2.4.2.1 Subtask - Write and replace a sample managed repo record through command APIs.
    - [ ] 2.4.2.2 Subtask - Prove duplicate identity writes return typed conflict errors.
    - [ ] 2.4.2.3 Subtask - Prove raw SPARQL diagnostics observe timeouts and graph allow-lists.
