# Phase 38 - Semantic Surface Hardening And Contributor Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit -->
<!-- covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery -->
<!-- covers: architecture.run_governance.run_detail_can_host_bounded_memory_context -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/package.spec.md`
- `../topology.md`
- `README.md`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `lib/jido_code/memory_graph/product_feedback.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/run_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `lib/jido_code_web/components/`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 35 through 37 established the stronger ontology split, typed governed references, capture/writer cutover, and bounded query/service adoption.
- Existing memory-aware surfaces such as repo detail, run detail, and workbench should now present typed governed context and feedback instead of generic artifact wording.
- This phase does not attempt the broader dashboard and remaining governed-surface rollout already scoped elsewhere; it hardens and converges the surfaces and verification paths that already depend on the stronger semantic model.
- Repositories may need bounded graph revalidation or rebuild after the ontology cutover, and that experience must remain product-owned and explainable.

[x] 38 Phase 38 - Semantic Surface Hardening And Contributor Convergence
  Harden the current memory-aware surfaces, verification flows, and contributor guidance around the stronger semantic model so the typed governed links become the durable default instead of a hidden implementation detail.

  [x] 38.1 Section - Product Surface Hardening For Typed Governed Semantics
    Update current memory-aware surfaces and feedback contracts so operators see typed governed context, clearer navigation, and non-generic action results.

    [x] 38.1.1 Task - Update existing memory-aware surfaces to render typed governed context
      Bring the current UI surfaces into line with the stronger semantic model without turning them into ontology browsers.

      [x] 38.1.1.1 Subtask - Update repo-detail, run-detail, and workbench memory surfaces to render typed governed links and labels rather than generic artifact wording.
      [x] 38.1.1.2 Subtask - Standardize surface-level memory action feedback around typed governed records, freshness, supersession, and recovery context.
      [x] 38.1.1.3 Subtask - Keep all surface behavior repository-scoped and product-owned, with no raw graph identifiers or ontology terms exposed as UI contracts.

    [x] 38.1.2 Task - Extract reusable surface helpers for the stronger semantic model
      Make the stronger semantic presentation reusable so later surface-rollout phases do not duplicate link, feedback, and status logic.

      [x] 38.1.2.1 Subtask - Extract shared governed-link and cross-graph navigation helpers for surfaces that already host bounded memory context.
      [x] 38.1.2.2 Subtask - Extract shared memory action feedback and recovery-state shaping helpers for LiveView or `live_vue` regions that need the stronger model.
      [x] 38.1.2.3 Subtask - Keep these helpers aligned to product services and view models rather than introducing UI-local semantic translation layers.

  [x] 38.2 Section - Verification, Rebuild, And Contributor Convergence
    Align recovery tooling, repo verification, docs, and topology guidance so the stronger semantic model is maintainable and explainable over time.

    [x] 38.2.1 Task - Add explicit verification and rebuild behavior for the semantic cutover
      Ensure repositories can detect, validate, and recover from old generic-artifact graph data through bounded repo-owned workflows.

      [x] 38.2.1.1 Subtask - Extend the existing memory verification path to validate the companion ontology, typed governed links, and repository-local graph coherence together.
      [x] 38.2.1.2 Subtask - Add bounded rebuild or revalidation guidance for repositories whose local graphs still reflect the older generic-artifact semantics.
      [x] 38.2.1.3 Subtask - Keep rebuild and validation behavior product-owned and explainable through the existing memory status and feedback surfaces.

    [x] 38.2.2 Task - Align contributor docs and architecture guidance to the stronger model
      Update repo documentation so future work builds on the stronger semantic model by default.

      [x] 38.2.2.1 Subtask - Update contributor docs and topology guidance to explain the companion control-plane ontology and typed governed-reference model.
      [x] 38.2.2.2 Subtask - Document the direct cutover expectation so new code does not reintroduce generic artifact semantics for governed links.
      [x] 38.2.2.3 Subtask - Keep the package and spec-led guidance explicit about where governed truth lives versus where semantic support links live.

  [x] 38.3 Section - Phase 38 Integration Tests
    Verify the stronger semantic model is visible, recoverable, and maintainable across current surfaces, rebuild flows, and contributor-facing verification.

    [x] 38.3.1 Task - Surface and recovery scenarios
      Prove the current memory-aware surfaces behave cleanly after the stronger semantic cutover.

      [x] 38.3.1.1 Subtask - Add coverage proving repo detail, run detail, and workbench render typed governed links and feedback without generic artifact wording.
      [x] 38.3.1.2 Subtask - Add coverage proving stale, invalidated, and rebuild-required states remain explainable through product-owned recovery flows.
      [x] 38.3.1.3 Subtask - Add coverage proving shared surface helpers preserve repository-scoped navigation and memory action behavior.

    [x] 38.3.2 Task - Verification and documentation scenarios
      Prove the repo’s verification and documentation surfaces are aligned to the stronger semantic model.

      [x] 38.3.2.1 Subtask - Add coverage proving the verification path checks the ontology pair, typed governed links, and graph coherence together.
      [x] 38.3.2.2 Subtask - Add coverage proving repository rebuild or revalidation guidance works for older generic-artifact graph state.
      [x] 38.3.2.3 Subtask - Verify the spec workspace, topology guide, and contributor docs remain coherent after Phase 38 converges the stronger semantic model.
