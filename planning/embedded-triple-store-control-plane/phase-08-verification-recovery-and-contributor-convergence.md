# Phase 8 - Verification, Recovery, And Contributor Convergence

Back to plan: [README](./README.md)

**Description:** This phase hardens the embedded TripleStore control plane after Ash/Postgres removal. It adds backup, restore, integrity checks, operational diagnostics, reset tooling, documentation, and durable quality gates for future contributors.

- [ ] 8 Phase - Verification, recovery, and contributor convergence.

  Description: Make the new embedded data plane operable, recoverable, and difficult to regress.

## 8.1 Section - Integrity And Recovery Tooling

**Description:** This section adds the operational tools needed to trust the embedded store.

- [x] 8.1 Section - Integrity and recovery tooling.

  Description: Operators and contributors need explicit ways to validate, inspect, reset, back up, and restore the control-plane store.

  - [x] 8.1.1 Task - Add integrity checks.

    Description: Integrity checks should verify graph presence, ontology version, required singleton records, identity uniqueness, and dangling links.

    - [x] 8.1.1.1 Subtask - Check required named graphs and ontology bootstrap triples.
    - [x] 8.1.1.2 Subtask - Check uniqueness identities for every codec registry entry.
    - [x] 8.1.1.3 Subtask - Check object links for missing target subjects where targets should exist.

  - [x] 8.1.2 Task - Add backup, restore, and reset commands.

    Description: Embedded storage needs first-class lifecycle commands instead of database-specific procedures.

    - [x] 8.1.2.1 Subtask - Add export to TriG or N-Quads with redaction rules for auth and security graphs.
    - [x] 8.1.2.2 Subtask - Add restore from exported graph files with ontology and version checks.
    - [x] 8.1.2.3 Subtask - Add dev/test reset commands that clear control-plane graphs and reload ontologies.

## 8.2 Section - Observability And Diagnostics

**Description:** This section makes store health and query behavior visible.

- [x] 8.2 Section - Observability and diagnostics.

  Description: Product surfaces and logs should explain store health without exposing raw graph details by default.

  - [x] 8.2.1 Task - Add telemetry and health status.

    Description: Store operations need duration, count, failure, timeout, and graph-size metrics.

    - [x] 8.2.1.1 Subtask - Emit telemetry for store open, query, update, export, restore, and integrity checks.
    - [x] 8.2.1.2 Subtask - Add health projections for ready, degraded, missing graph, stale ontology, and recovery required.
    - [x] 8.2.1.3 Subtask - Surface bounded diagnostics on setup, dashboard, and repo-detail runtime panels.

  - [x] 8.2.2 Task - Add diagnostic query tooling.

    Description: Contributors need safe ways to inspect graph state during development and support.

    - [x] 8.2.2.1 Subtask - Add a Mix task for named safe queries over product records.
    - [x] 8.2.2.2 Subtask - Add a raw SPARQL diagnostic command gated by explicit flags and limits.
    - [x] 8.2.2.3 Subtask - Add docs showing how to inspect a record by subject IRI and graph name.

## 8.3 Section - Documentation And Guardrails

**Description:** This section updates contributor guidance so future work uses the embedded store correctly.

- [ ] 8.3 Section - Documentation and guardrails.

  Description: The new persistence architecture should become the default mental model in docs, tests, and code review.

  - [ ] 8.3.1 Task - Update developer documentation.

    Description: Docs should explain the store boundary, ontology, codecs, graph topology, and verification commands.

    - [ ] 8.3.1.1 Subtask - Update repository mental map and development workflow docs.
    - [ ] 8.3.1.2 Subtask - Add a control-plane ontology and query examples guide.
    - [ ] 8.3.1.3 Subtask - Document when to use product query helpers versus explicit SPARQL.

  - [ ] 8.3.2 Task - Add regression guardrails.

    Description: Future contributors should get fast feedback if they reintroduce the removed data plane or bypass product boundaries.

    - [ ] 8.3.2.1 Subtask - Add static checks for forbidden Ash/Ecto imports and direct TripleStore calls outside allowed modules.
    - [ ] 8.3.2.2 Subtask - Add codec registry completeness checks.
    - [ ] 8.3.2.3 Subtask - Add graph redaction checks for auth and security records.

## 8.4 Section - Integration Tests

**Description:** This final section proves the completed embedded data plane is recoverable, observable, documented, and guarded.

- [ ] 8.4 Section - Integration tests.

  Description: Final gates should combine product smoke, integrity, backup, restore, and static regression checks.

  - [ ] 8.4.1 Task - Add full embedded-store verification gate.

    Description: One Mix task should run the focused checks needed after persistence-boundary changes.

    - [ ] 8.4.1.1 Subtask - Add `mix control_plane.verify` or equivalent.
    - [ ] 8.4.1.2 Subtask - Include ontology parse/load, codec round-trip, store contract, integrity, and static dependency checks.
    - [ ] 8.4.1.3 Subtask - Include product smoke tests that do not require Postgres.

  - [ ] 8.4.2 Task - Add backup and recovery integration coverage.

    Description: Recovery tests should prove the embedded control plane can be exported, restored, and used after restart.

    - [ ] 8.4.2.1 Subtask - Bootstrap a store, create representative records, export graph files, and close the store.
    - [ ] 8.4.2.2 Subtask - Restore into a new store path and verify product projections match.
    - [ ] 8.4.2.3 Subtask - Restart the application against the restored store and run the product smoke scenario.
