# Product Foundation Docs

This subject defines the core documentation that explains what `Jido.Code` is trying to
be, how it approaches implementation, and how its first durable data model is shaped.

```spec-meta
id: docs.product_foundation
kind: feature
status: active
summary: Jido.Code publishes a concise vision doc, a terse technical implementation doc, a first data ontology doc, and repository-level doc indexes that point operators and contributors to those foundational materials alongside the adjacent contributor guides.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.local_developer_workflow
  - jido_code.canonical_repo_surface
surface:
  - docs/VISION.md
  - docs/TECHNICAL_IMPLEMENTATION.md
  - docs/DATA_ONTOLOGY.md
  - docs/factory_gaps.md
  - docs/README.md
  - README.md
```

## Requirements

```spec-requirements
- id: docs.product_foundation.vision_defined
  statement: The repository shall publish a vision document that states the core product idea, what Jido.Code is building, the trust model, and the initial scope.
  priority: must
  stability: evolving

- id: docs.product_foundation.technical_approach_defined
  statement: The repository shall publish a technical implementation document that states the technical stance, the durable control loop, and the intended Ash domain layout.
  priority: must
  stability: evolving

- id: docs.product_foundation.data_ontology_defined
  statement: The repository shall publish a first data ontology that defines the preferred control-plane record names, their relationships, and the initial Ash resource framing.
  priority: must
  stability: evolving

- id: docs.product_foundation.factory_gap_note_present
  statement: The repository shall publish a Jido-centric product comparison note that captures what Jido.Code should learn from Factory.ai and where it should deliberately differentiate.
  priority: should
  stability: evolving

- id: docs.product_foundation.docs_index_present
  statement: The repository shall expose the foundation docs through both docs/README.md and the top-level README documentation section while linking adjacent contributor guides, including the separate desktop packaging guide, the repo-local spec workflow, and the direct Mix-based CLI surfaces.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: docs.product_foundation.scenario.new_contributor_reads_foundation
  covers:
    - docs.product_foundation.vision_defined
    - docs.product_foundation.technical_approach_defined
    - docs.product_foundation.data_ontology_defined
    - docs.product_foundation.factory_gap_note_present
  given:
    - A contributor wants to understand what Jido.Code is trying to build before editing implementation code.
  when:
    - The contributor reads the foundation docs.
  then:
    - The docs explain the product thesis, the technical stance, the base control-plane model, and how Jido.Code should position itself relative to adjacent agent-development products without requiring code spelunking.

- id: docs.product_foundation.scenario.docs_are_discoverable
  covers:
    - docs.product_foundation.docs_index_present
  given:
    - A contributor starts from the docs index or the repository README.
  when:
    - The contributor looks for foundational product documentation.
  then:
    - The vision, technical implementation, and data ontology docs are linked directly.
```

## Verification

```spec-verification
- kind: source_file
  target: docs/VISION.md
  covers:
    - docs.product_foundation.vision_defined

- kind: source_file
  target: docs/TECHNICAL_IMPLEMENTATION.md
  covers:
    - docs.product_foundation.technical_approach_defined

- kind: source_file
  target: docs/DATA_ONTOLOGY.md
  covers:
    - docs.product_foundation.data_ontology_defined

- kind: source_file
  target: docs/factory_gaps.md
  covers:
    - docs.product_foundation.factory_gap_note_present

- kind: source_file
  target: docs/README.md
  covers:
    - docs.product_foundation.docs_index_present

- kind: source_file
  target: README.md
  covers:
    - docs.product_foundation.docs_index_present
```
