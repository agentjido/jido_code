# Phase 30 - Durable Coding Memory Adoption And Validation

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/memory_ontology.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `lib/jido_code/source_code_graph/workflow_service.ex`
- `lib/jido_code/source_code_graph/governed_adoption.ex`
- `lib/jido_code/source_code_graph/materialization.ex`
- `lib/jido_code/governance/`
- `test/jido_code/`

## Relevant Assumptions / Defaults
- Phase 29 has already established the bounded workflow provenance capture seam.
- The next step is durable memory, which must be more selective than provenance insertion.
- Durable memories should only be inserted after explicit classification or governed adoption.
- Freshness, validation, and invalidation must evolve with revision movement and test evidence.

[ ] 30 Phase 30 - Durable Coding Memory Adoption And Validation
  Add the durable memory insertion and update behavior that turns selected findings, decisions, conventions, issues, and lessons into reusable coding memory over time.

  [ ] 30.1 Section - Durable Memory Classification And Adoption
    Create the bounded product and governed entrypoints that decide when a semantic or workflow outcome deserves durable memory insertion.

    [ ] 30.1.1 Task - Introduce classified durable memory insertion
      Add the insertion boundary that accepts explicitly classified durable memories and writes them into the `memory` graph.

      [ ] 30.1.1.1 Subtask - Support insertion of Fact, Decision, LessonLearned, Invariant, Convention, KnownIssue, OpenQuestion, Pattern, and AntiPattern.
      [ ] 30.1.1.2 Subtask - Require explicit classification or adoption metadata rather than accepting ambient runtime output as memory.
      [ ] 30.1.1.3 Subtask - Ensure inserted memories link to source-code entities, workflow provenance, and governed product context when available.

    [ ] 30.1.2 Task - Connect product and governed adoption seams
      Let product-owned workflow and governed-adoption boundaries turn meaningful findings into durable memory without bypassing the capture plane.

      [ ] 30.1.2.1 Subtask - Allow semantic workflow services to propose bounded durable memories intentionally.
      [ ] 30.1.2.2 Subtask - Allow governed adoption paths to insert durable decision, lesson, issue, or convention memory when the factory explicitly adopts the finding.
      [ ] 30.1.2.3 Subtask - Keep memory insertion separate from merely materializing governed Observation, Assessment, WorkItem, Evidence, or Decision records.

  [ ] 30.2 Section - Freshness, Validation, And Invalidation
    Add the metadata and update behavior that keeps durable memory explainable as repositories evolve.

    [ ] 30.2.1 Task - Introduce freshness and validation updates
      Record how durable memories remain valid, become stale, or get revalidated over time.

      [ ] 30.2.1.1 Subtask - Update `freshnessScore`, `lastValidatedAt`, and `validForRevision` when revision or validation evidence is available.
      [ ] 30.2.1.2 Subtask - Attach `validatedByTestRun`, `supportedBy`, and related evidence links when tests or review outputs confirm a memory.
      [ ] 30.2.1.3 Subtask - Preserve bounded typed outcomes when freshness or validation evidence cannot be computed safely.

    [ ] 30.2.2 Task - Introduce invalidation and supersession behavior
      Let the system express when durable memory no longer applies or has been superseded.

      [ ] 30.2.2.1 Subtask - Record `invalidatedByRevision` and `staleReason` when revision movement or explicit review invalidates a memory.
      [ ] 30.2.2.2 Subtask - Support decision supersession through `supersedes` and `decisionStatus`.
      [ ] 30.2.2.3 Subtask - Ensure queries can distinguish durable but invalidated memory from still-valid memory.

  [ ] 30.3 Section - Phase 30 Integration Tests
    Verify durable memory is inserted only through explicit adoption paths and remains explainable under later validation and invalidation.

    [ ] 30.3.1 Task - Durable memory adoption scenarios
      Prove classified findings can become durable memory only through bounded product or governed seams.

      [ ] 30.3.1.1 Subtask - Add coverage proving classified findings can become durable memory instances of the intended ontology classes.
      [ ] 30.3.1.2 Subtask - Add coverage proving unadopted transient model output does not become durable memory.
      [ ] 30.3.1.3 Subtask - Add coverage proving durable memory links back to source-code entities and workflow provenance where available.

    [ ] 30.3.2 Task - Freshness and invalidation scenarios
      Prove durable memory remains queryable and explainable as repository state changes.

      [ ] 30.3.2.1 Subtask - Add coverage proving revision and test evidence update validation metadata.
      [ ] 30.3.2.2 Subtask - Add coverage proving invalidated or superseded memory remains explicit rather than silently disappearing.
      [ ] 30.3.2.3 Subtask - Verify the spec workspace remains coherent after durable memory adoption and validation land.
