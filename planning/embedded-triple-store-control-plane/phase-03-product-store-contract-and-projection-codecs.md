# Phase 3 - Product Store Contract And Projection Codecs

Back to plan: [README](./README.md)

**Description:** This phase creates the product-facing store contract and the codecs that map Elixir structs or maps to RDF quads. It replaces Ash resource actions with explicit product services while keeping callers insulated from raw RDF.

- [ ] 3 Phase - Product store contract and projection codecs.

  Description: Build the translation layer between product records and semantic graph storage.

## 3.1 Section - Store Behaviour

**Description:** This section defines the dependency boundary that all domains call instead of Ash.

- [x] 3.1 Section - Store behaviour.

  Description: A single behaviour keeps the TripleStore implementation replaceable in tests while preventing direct store calls from web or workflow modules.

  - [x] 3.1.1 Task - Define `JidoCode.ControlPlane.Store`.

    Description: The behaviour should model product persistence operations rather than RDF implementation details.

    - [x] 3.1.1.1 Subtask - Define callbacks for create, update, upsert, delete, get, list, append_event, and query.
    - [x] 3.1.1.2 Subtask - Define common request, actor, authorization context, and outcome structs.
    - [x] 3.1.1.3 Subtask - Define typed error structs for validation, conflict, not found, unavailable, and unauthorized outcomes.

  - [x] 3.1.2 Task - Add in-memory fake store for tests.

    Description: Unit tests should not need RocksDB unless they are verifying store integration.

    - [x] 3.1.2.1 Subtask - Implement a deterministic fake that honors the behaviour and identity conflicts.
    - [x] 3.1.2.2 Subtask - Add helpers for seeding records and reading written events.
    - [x] 3.1.2.3 Subtask - Keep fake semantics aligned with TripleStore contract tests.

## 3.2 Section - RDF Projection Codecs

**Description:** This section maps product records into RDF quads and back into product projections.

- [x] 3.2 Section - RDF projection codecs.

  Description: Codecs should be explicit modules per record family, not ad hoc string builders scattered through services.

  - [x] 3.2.1 Task - Define codec behaviour and registry.

    Description: Every product record family should declare its class IRI, graph, subject builder, identity keys, and field mappings.

    - [x] 3.2.1.1 Subtask - Add callbacks for encode, decode, subject_iri, class_iri, graph_iri, and identity_queries.
    - [x] 3.2.1.2 Subtask - Add a registry that maps product type names to codec modules.
    - [x] 3.2.1.3 Subtask - Validate at compile or test time that all planned classes have codecs or explicit exclusions.

  - [x] 3.2.2 Task - Implement core scalar and metadata mapping.

    Description: Shared scalar encoding keeps ids, atoms, timestamps, booleans, arrays, and maps consistent.

    - [x] 3.2.2.1 Subtask - Encode ids and atoms as strings with explicit normalization.
    - [x] 3.2.2.2 Subtask - Encode datetimes as `xsd:dateTime` literals.
    - [x] 3.2.2.3 Subtask - Encode bounded maps as canonical JSON literals until promoted to semantic nodes.

## 3.3 Section - Validation And Authorization Replacement

**Description:** This section replaces Ash changesets and policies with product-owned validators and guards.

- [x] 3.3 Section - Validation and authorization replacement.

  Description: Validation and authorization must be explicit before product callers switch to the new store.

  - [x] 3.3.1 Task - Add command validators.

    Description: Each write command should validate required fields, enum values, identity fields, and lifecycle transitions.

    - [x] 3.3.1.1 Subtask - Define reusable validators for required string, atom enum, map, datetime, and relationship fields.
    - [x] 3.3.1.2 Subtask - Define per-family validators for setup, control, operations, governance, orchestration, conversations, execution runtime, auth, and security records.
    - [x] 3.3.1.3 Subtask - Return structured validation errors suitable for LiveView forms and workflow callers.

  - [x] 3.3.2 Task - Add policy guards.

    Description: Existing Ash policy intent should become explicit policy functions near product services.

    - [x] 3.3.2.1 Subtask - Define human operator, machine actor, setup bootstrap, and system actor contexts.
    - [x] 3.3.2.2 Subtask - Add read and mutate authorization checks for each record family.
    - [x] 3.3.2.3 Subtask - Add audit metadata for authorized and denied mutations.

## 3.4 Section - Integration Tests

**Description:** This final section proves product records can round-trip through codecs and the store contract without Ash.

- [ ] 3.4 Section - Integration tests.

  Description: Contract tests should exercise both the fake store and embedded TripleStore implementation.

  - [ ] 3.4.1 Task - Add codec round-trip tests.

    Description: Codec tests should prove data shape, identity, and graph placement are deterministic.

    - [ ] 3.4.1.1 Subtask - Round-trip representative records from every product family.
    - [ ] 3.4.1.2 Subtask - Assert generated quads use expected class, subject, graph, and predicate IRIs.
    - [ ] 3.4.1.3 Subtask - Assert excluded secret fields never appear in encoded quads.

  - [ ] 3.4.2 Task - Add store contract tests.

    Description: Store implementations should pass the same product-level behaviour tests.

    - [ ] 3.4.2.1 Subtask - Run create, update, upsert, lookup, delete, and append-event tests against fake store.
    - [ ] 3.4.2.2 Subtask - Run the same tests against a temporary embedded TripleStore path.
    - [ ] 3.4.2.3 Subtask - Assert authorization and validation errors match across implementations.
