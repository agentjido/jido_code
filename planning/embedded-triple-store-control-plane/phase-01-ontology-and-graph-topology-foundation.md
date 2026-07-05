# Phase 1 - Ontology And Graph Topology Foundation

Back to plan: [README](./README.md)

**Description:** This phase makes the embedded semantic data plane explicit before any runtime code depends on it. It finishes the control-plane ontology shape, canonical IRI rules, named graph topology, and graph ownership decisions needed to replace Ash/Postgres without a migration bridge.

- [ ] 1 Phase - Ontology and graph topology foundation.

  Description: Define the semantic schema and graph layout that all later store code uses as product truth.

## 1.1 Section - Canonical Control-Plane Ontology

**Description:** This section expands the control-plane ontology from a memory-link companion into the schema source for product records.

- [ ] 1.1 Section - Canonical control-plane ontology.

  Description: Keep the ontology broad enough to model all current Ash resource families while avoiding raw secret material and unbounded payload dumps.

  - [ ] 1.1.1 Task - Complete class coverage for current product record families.

    Description: Every current Ash-backed resource family needs a corresponding semantic class or documented exclusion.

    - [ ] 1.1.1.1 Subtask - Cover control, operations, governance, orchestration, conversations, execution runtime, accounts, auth providers, GitHub, security, setup, and legacy project classes.
    - [ ] 1.1.1.2 Subtask - Mark previous-era records such as `Project` and `WorkflowRun` as compatibility concepts, not preferred new data-plane classes.
    - [ ] 1.1.1.3 Subtask - Document which sensitive fields are intentionally excluded from semantic projection.

  - [ ] 1.1.2 Task - Define shared predicates for common resource fields.

    Description: Common ids, statuses, timestamps, labels, source keys, and metadata projections should reuse stable predicates instead of per-class vocabulary drift.

    - [ ] 1.1.2.1 Subtask - Add shared id, label, status, kind, inserted-at, updated-at, metadata, and payload predicates.
    - [ ] 1.1.2.2 Subtask - Define provider, canonical key, canonical reference, title, summary, and priority predicates.
    - [ ] 1.1.2.3 Subtask - Reserve JSON literal predicates for bounded map fields that are not yet query-critical.

## 1.2 Section - Canonical IRI Rules

**Description:** This section defines deterministic IRIs so resources can be written, replaced, linked, and queried without database surrogate assumptions.

- [ ] 1.2 Section - Canonical IRI rules.

  Description: Use stable product IRIs based on resource class and record id, with explicit rules for natural identities.

  - [ ] 1.2.1 Task - Define IRI templates for every record class.

    Description: Each class needs one canonical subject IRI template and any alternate lookup keys must be modeled as predicates.

    - [ ] 1.2.1.1 Subtask - Define templates under `https://jido.run/control/...` for product-owned records.
    - [ ] 1.2.1.2 Subtask - Define repo-scoped templates for records whose identity is local to a managed repository.
    - [ ] 1.2.1.3 Subtask - Define external-object templates that preserve provider, host, object type, and external id.

  - [ ] 1.2.2 Task - Define identity and uniqueness contracts.

    Description: Ash identities must become explicit semantic uniqueness rules enforced by store code.

    - [ ] 1.2.2.1 Subtask - Inventory current identity constraints and map each to an IRI template or uniqueness query.
    - [ ] 1.2.2.2 Subtask - Define conflict errors for duplicate natural identities.
    - [ ] 1.2.2.3 Subtask - Define idempotent upsert semantics for singleton, projection, and external-object records.

## 1.3 Section - Named Graph Topology

**Description:** This section decides which named graph owns each kind of product fact.

- [ ] 1.3 Section - Named graph topology.

  Description: Keep product records, events, auth, security, conversations, execution runtime, memory, workflow provenance, and source code isolated but linkable.

  - [ ] 1.3.1 Task - Define graph ownership rules.

    Description: Every write path should know which graph receives its triples before store adapters exist.

    - [ ] 1.3.1.1 Subtask - Assign control, operations, governance, and orchestration records to `control_plane`.
    - [ ] 1.3.1.2 Subtask - Assign append-only lifecycle events to `control_plane_events` unless they belong to conversation or execution runtime graphs.
    - [ ] 1.3.1.3 Subtask - Assign auth, security, conversations, and execution runtime records to their dedicated named graphs.

  - [ ] 1.3.2 Task - Define cross-graph link rules.

    Description: Cross-graph links should use object IRIs and product-owned helpers, not raw graph traversal from UI code.

    - [ ] 1.3.2.1 Subtask - Define how memory and workflow provenance link to governed records.
    - [ ] 1.3.2.2 Subtask - Define how source-code entities link to work items, runs, evidence, and memories.
    - [ ] 1.3.2.3 Subtask - Define degraded behavior when a sibling graph is stale, missing, or unavailable.

## 1.4 Section - Integration Tests

**Description:** This final section proves the ontology and graph topology are parseable, loadable, and queryable before implementation starts.

- [ ] 1.4 Section - Integration tests.

  Description: Validate the semantic schema as an executable artifact instead of treating it as documentation only.

  - [ ] 1.4.1 Task - Add ontology parsing and load coverage.

    Description: The ontology files must parse and load into the embedded quad store with the intended named graph identity.

    - [ ] 1.4.1.1 Subtask - Parse `jido-control-plane.ttl` and `jido-memory.ttl` through `RDF.Turtle.read_file/1`.
    - [ ] 1.4.1.2 Subtask - Load both ontologies into a temporary `triple_store` quad store.
    - [ ] 1.4.1.3 Subtask - Query for representative classes and predicates from each product family.

  - [ ] 1.4.2 Task - Add topology contract coverage.

    Description: Graph identity, IRI template, and ownership decisions should be testable before runtime writes exist.

    - [ ] 1.4.2.1 Subtask - Assert all named graph IRIs are exposed through one product-owned registry.
    - [ ] 1.4.2.2 Subtask - Assert every planned record class has a canonical IRI builder.
    - [ ] 1.4.2.3 Subtask - Assert no security ontology projection includes secret material predicates.
