# Phase 35 - Governed Control-Plane Ontology And Typed Reference Foundation

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_ontology.memories_anchor_to_code_entities_and_symbols -->
<!-- covers: architecture.memory_ontology.workflow_and_llm_provenance_entities_are_modeled -->
<!-- covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance -->
<!-- covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_ontology.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/event_assessment_synthesis.spec.md`
- `../specs/work_synthesis.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.namespace_and_control_naming.md`
- `../topology.md`
- `priv/ontologies/`
- `lib/jido_code/memory_graph.ex`
- `lib/jido_code/memory_graph/`
- `lib/jido_code/governance/`
- `lib/jido_code/operations/`
- `test/jido_code/`

## Relevant Assumptions / Defaults
- The existing `jido-memory.ttl` already models durable memory and workflow provenance well, but governed product records are still represented indirectly through generic artifact-style links.
- The stronger semantic model keeps the existing three named graphs: `source_code`, `memory`, and `workflow_provenance`.
- This phase does not introduce a fourth governance graph. Instead, governed product records become first-class typed entities when memory and provenance link to them.
- The stronger model uses a companion ontology file for governed product records instead of overloading `jido-memory.ttl` with mixed concerns.
- This repo is greenfield after current-truth updates, so the rollout may cut over directly rather than preserving long-lived compatibility shapes for old generic governed links.

[x] 35 Phase 35 - Governed Control-Plane Ontology And Typed Reference Foundation
  Establish the companion control-plane ontology and canonical typed governed-reference contract so memory and provenance can link to governed product records semantically instead of through generic artifact identifiers.

  [x] 35.1 Section - Companion Control-Plane Ontology
    Introduce the ontology asset and semantic vocabulary that let governed product records participate in the stronger semantic model without collapsing memory and control-plane concepts into one file.

    [x] 35.1.1 Task - Add the companion control-plane ontology asset and namespace
      Create the ontology file, namespace, and conceptual split that keep coding memory and governed product records distinct but linkable.

      [x] 35.1.1.1 Subtask - Add a companion ontology file under `priv/ontologies/` for governed product records and their canonical namespace.
      [x] 35.1.1.2 Subtask - Keep `jido-memory.ttl` focused on memory and workflow provenance, with cross-ontology references into the governed control-plane ontology rather than duplicate class definitions.
      [x] 35.1.1.3 Subtask - Preserve the distinction between memory `Decision` and governed `Decision` through ontology namespace and documentation rather than by relying on ambiguous labels.

    [x] 35.1.2 Task - Model governed product records and their canonical relations
      Encode the product records that already exist in `jido_code` as first-class ontology concepts and relationships so semantic links match product truth.

      [x] 35.1.2.1 Subtask - Model `ManagedRepo`, `Event`, `Observation`, `Assessment`, `WorkItem`, `Run`, `Evidence`, `ChangeRequest`, and governed `Decision` as first-class classes.
      [x] 35.1.2.2 Subtask - Model the canonical control-plane relationships among those records, including demand interpretation, work synthesis, run governance, and review history.
      [x] 35.1.2.3 Subtask - Define stable repository-scoped IRIs and labels for governed product records so later memory and provenance links do not rely on generic artifact paths.

  [x] 35.2 Section - Typed Governed Reference Contract
    Define the code-level contract that turns product record ids and generic artifact paths into one typed governed-reference model reused across capture, query, navigation, and UI shaping.

    [x] 35.2.1 Task - Add canonical governed-reference helpers and normalization rules
      Introduce one product-owned helper boundary for typed governed IRIs and reference metadata so later phases do not re-invent link semantics in envelopes or services.

      [x] 35.2.1.1 Subtask - Add canonical IRI helpers for governed record kinds such as `run`, `work_item`, `evidence`, `decision`, `observation`, `assessment`, `change_request`, and `managed_repo`.
      [x] 35.2.1.2 Subtask - Define one normalized governed-reference shape that carries kind, id, iri, and label inputs without falling back to generic `artifact` naming.
      [x] 35.2.1.3 Subtask - Replace the plan-level assumption that generic artifact paths are the durable contract for governed references.

    [x] 35.2.2 Task - Align current-truth docs and topology to the stronger semantic model
      Update the spec workspace so the stronger model is explicit about the ontology split, typed governed links, and no-new-graph constraint.

      [x] 35.2.2.1 Subtask - Update the relevant ADR/spec subjects to describe the companion control-plane ontology and typed governed-reference contract.
      [x] 35.2.2.2 Subtask - Update `.spec/topology.md` so the architecture diagrams and concept descriptions show governed product records as first-class semantic entities.
      [x] 35.2.2.3 Subtask - Keep the planning and package guidance explicit that the stronger semantic model still preserves governed product records as the business system of record.

  [x] 35.3 Section - Phase 35 Integration Tests
    Verify the ontology split, IRI contract, and current-truth workspace before later phases cut over runtime capture and product services.

    [x] 35.3.1 Task - Ontology and governed-reference contract scenarios
      Prove the semantic foundation is loadable, unambiguous, and aligned to product naming.

      [x] 35.3.1.1 Subtask - Add coverage proving the companion ontology loads alongside `jido-memory.ttl` without namespace ambiguity.
      [x] 35.3.1.2 Subtask - Add coverage proving canonical governed IRI helpers generate stable repository-scoped identifiers for each governed record kind.
      [x] 35.3.1.3 Subtask - Add coverage proving the stronger model still uses the existing `source_code`, `memory`, and `workflow_provenance` graphs rather than introducing a governance graph.

    [x] 35.3.2 Task - Spec and topology coherence scenarios
      Prove the workspace explains the stronger semantic model consistently before runtime code starts depending on it.

      [x] 35.3.2.1 Subtask - Verify the relevant ADR and subject specs all describe the same ontology split and typed governed-link model.
      [x] 35.3.2.2 Subtask - Verify `.spec/topology.md` remains aligned with the current semantic planes and product routes.
      [x] 35.3.2.3 Subtask - Verify the spec workspace remains coherent after Phase 35 adds the stronger semantic foundation.
