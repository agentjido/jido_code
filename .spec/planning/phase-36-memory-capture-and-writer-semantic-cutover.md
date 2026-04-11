# Phase 36 - Memory Capture And Writer Semantic Cutover

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary -->
<!-- covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples -->
<!-- covers: architecture.memory_ontology.memory_updates_preserve_mutation_lineage -->
<!-- covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/memory_ontology.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `priv/ontologies/`
- `lib/jido_code/memory_graph/capture_envelope.ex`
- `lib/jido_code/memory_graph/capture_writer.ex`
- `lib/jido_code/memory_graph/durable_memory_envelope.ex`
- `lib/jido_code/memory_graph/durable_memory_writer.ex`
- `lib/jido_code/memory_graph/durable_memory_update_envelope.ex`
- `lib/jido_code/memory_graph/durable_memory_update_writer.ex`
- `lib/jido_code/source_code_graph/memory_capture.ex`
- `lib/jido_code/source_code_graph/materialization.ex`
- `lib/jido_code/source_code_graph/governed_adoption.ex`
- `lib/jido_code/agent_workspace.ex`
- `test/jido_code/`

## Relevant Assumptions / Defaults
- Phase 35 established the companion control-plane ontology, canonical governed IRIs, and one typed governed-reference contract.
- The current capture and writer path still treats most governed links as generic `artifact` references and often types them as `EvidenceArtifact`.
- This phase is a direct cutover: runtime and product callers should move to typed governed references instead of preserving parallel generic-artifact write shapes.
- True evidence or support artifacts may remain `EvidenceArtifact` entities, but governed product records must no longer be flattened into that class.

[ ] 36 Phase 36 - Memory Capture And Writer Semantic Cutover
  Cut the capture plane and graph writers over to typed governed references so durable memory, workflow provenance, and memory updates all emit stronger governed semantics instead of generic artifact links.

  [x] 36.1 Section - Envelope And Capture Request Cutover
    Replace the generic governed context shapes used by capture callers with typed governed-reference contracts across memory, provenance, and update flows.

    [x] 36.1.1 Task - Replace generic governed-artifact normalization in capture envelopes
      Update the envelope layer so typed governed references become the canonical capture input and later phases no longer have to reverse-engineer semantics from artifact paths.

      [x] 36.1.1.1 Subtask - Replace generic governed-artifact parsing in `CaptureEnvelope`, `DurableMemoryEnvelope`, and `DurableMemoryUpdateEnvelope` with typed governed-reference normalization.
      [x] 36.1.1.2 Subtask - Distinguish governed product references from true evidence or support artifacts so the envelope output preserves semantic intent.
      [x] 36.1.1.3 Subtask - Remove plan-level reliance on `artifact_paths` or generic id-map fallbacks as the preferred write contract.

    [x] 36.1.2 Task - Align existing runtime and product callers to the typed capture contract
      Update the current write seams so they emit the stronger semantic references rather than leaving the writers to guess intent.

      [x] 36.1.2.1 Subtask - Update `AgentWorkspace`, source-code-graph memory capture, and governed-adoption paths to emit typed governed references in capture requests.
      [x] 36.1.2.2 Subtask - Update materialization and follow-up helpers so created `Observation`, `Assessment`, `WorkItem`, `Evidence`, and `Decision` links are emitted as typed references immediately.
      [x] 36.1.2.3 Subtask - Keep all callers on the canonical capture plane rather than introducing side-channel semantic writes during the cutover.

  [x] 36.2 Section - Writer Semantic Cutover
    Change the graph writers so the stored triples reflect typed governed relationships directly and preserve evidence semantics only where they truly apply.

    [x] 36.2.1 Task - Emit typed governed triples from memory and provenance writers
      Replace generic support links with explicit governed-context relationships and keep memory mutation lineage intact.

      [x] 36.2.1.1 Subtask - Update the provenance writer to emit typed governed relations for runs, work items, evidence, decisions, observations, assessments, and change requests.
      [x] 36.2.1.2 Subtask - Update the durable-memory writer so governed product records stop being typed as generic `EvidenceArtifact` entities.
      [x] 36.2.1.3 Subtask - Update the durable-memory update writer so validate, invalidate, and supersede operations preserve typed governed references along with freshness and mutation lineage.

    [x] 36.2.2 Task - Keep graph-store status and rebuild behavior coherent during the cutover
      Preserve the existing named-graph layout while making the semantic cutover explicit enough that repositories can rebuild or revalidate cleanly.

      [x] 36.2.2.1 Subtask - Preserve the existing `memory` and `workflow_provenance` named graphs while updating the triples written into them.
      [x] 36.2.2.2 Subtask - Add bounded invalidation, rebuild, or revalidation behavior for repositories whose stored graph data still reflects the older generic-artifact semantics.
      [x] 36.2.2.3 Subtask - Surface typed-cutover readiness and recovery state through the existing memory-graph status path instead of hidden migration assumptions.

  [ ] 36.3 Section - Phase 36 Integration Tests
    Verify the capture plane, writers, and store-status paths all emit the stronger governed semantics consistently before query and product services depend on them.

    [ ] 36.3.1 Task - Envelope and writer cutover scenarios
      Prove memory, provenance, and update writes now store typed governed semantics rather than generic artifacts.

      [ ] 36.3.1.1 Subtask - Add coverage proving capture envelopes normalize governed references into typed kinds and IRIs.
      [ ] 36.3.1.2 Subtask - Add coverage proving writers emit typed governed links while preserving true evidence/support artifacts as evidence semantics only.
      [ ] 36.3.1.3 Subtask - Add coverage proving validate, invalidate, and supersede updates preserve typed governed context plus freshness and mutation lineage.

    [ ] 36.3.2 Task - Graph-status and rebuild scenarios
      Prove repository-local graph state remains explainable and recoverable through the semantic cutover.

      [ ] 36.3.2.1 Subtask - Add coverage proving repositories can detect stale generic-artifact graph state and request bounded revalidation or rebuild.
      [ ] 36.3.2.2 Subtask - Add coverage proving the named-graph layout remains unchanged while semantic triples become stronger.
      [ ] 36.3.2.3 Subtask - Verify the spec workspace remains coherent after Phase 36 cuts over the capture plane and writers.
