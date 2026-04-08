# Phase 23 - Source Code Graph Hardening and Operational Convergence

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_pod.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/package.spec.md`
- `../specs/product_foundation_docs.spec.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/pods/`
- `lib/jido_code/agents/`
- `lib/jido_code/actions/`
- `README.md`
- `CONTRIBUTING.md`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults
- Phases 20 through 22 have established the SourceCodeGraphPod contract, full-mode ontology analysis, coherent `source_code` graph ingestion, and SPARQL-backed query entrypoints.
- The next step is operational hardening: revision coherence, failure visibility, contributor guidance, and end-to-end pod confidence.
- Semantic source-code graph capability remains repository-scoped and bounded; it is not the product's durable control-plane truth.

[ ] 23 Phase 23 - Source Code Graph Hardening and Operational Convergence
  Harden the repository semantic graph capability so refresh, failure handling, contributor guidance, and end-to-end pod scenarios are durable enough for regular product use.

  [ ] 23.1 Section - Revision Coherence and Failure Recovery
    Strengthen refresh, snapshot identity, and failure behavior so repository semantic graph state remains explainable under change and failure.

    [ ] 23.1.1 Task - Harden graph revision tracking
      Make graph freshness and revision identity explicit enough for operators and dependent workflows to reason about semantic state safely.

      [ ] 23.1.1.1 Subtask - Record stable repository revision metadata alongside the latest successful `source_code` load.
      [ ] 23.1.1.2 Subtask - Detect and surface stale graph state when the workspace revision has moved beyond the last loaded graph revision.
      [ ] 23.1.1.3 Subtask - Define safe behavior for callers when semantic graph revision is stale but still queryable.

    [ ] 23.1.2 Task - Harden failure and degraded-state behavior
      Keep semantic capability trustworthy by surfacing analysis, load, and query failures as explicit, recoverable repository-scoped state.

      [ ] 23.1.2.1 Subtask - Persist latest failure kind, message, and stage in graph-context state.
      [ ] 23.1.2.2 Subtask - Define retry and recovery entrypoints for failed analysis or load attempts.
      [ ] 23.1.2.3 Subtask - Ensure query callers receive bounded degraded-state outcomes instead of raw store or ontology exceptions.

  [ ] 23.2 Section - Contributor and Operational Convergence
    Align the repo’s docs, start surfaces, and maintenance expectations so the new semantic graph capability is understandable and maintainable by contributors.

    [ ] 23.2.1 Task - Update contributor-facing guidance
      Document the SourceCodeGraphPod capability and its dependency expectations in repo-owned docs and contributor instructions.

      [ ] 23.2.1.1 Subtask - Add README and contributor guidance for semantic graph dependencies and local setup assumptions.
      [ ] 23.2.1.2 Subtask - Document the repository-scoped `source_code` graph lifecycle and explicit analyze/load/query workflow.
      [ ] 23.2.1.3 Subtask - Document when higher-level workflows should rely on the semantic graph versus ordinary file/code tools.

    [ ] 23.2.2 Task - Align operational verification surfaces
      Make the new capability visible to repo-owned verification paths without turning it into an opaque local-only convention.

      [ ] 23.2.2.1 Subtask - Add repo-owned checks or test groupings for semantic graph analysis, load, and query coverage.
      [ ] 23.2.2.2 Subtask - Ensure contributor guidance references the semantic graph verification path in the current stack.
      [ ] 23.2.2.3 Subtask - Keep graph-store and ontology dependencies version-controlled and explicit in repo-owned setup surfaces.

  [ ] 23.3 Section - Phase 23 Integration Tests
    Verify the hardened semantic graph capability remains repository-scoped, revision-aware, failure-explainable, and contributor-maintainable in end-to-end scenarios.

    [ ] 23.3.1 Task - Revision and recovery scenarios
      Prove the pod can detect stale graph state, refresh coherently, and recover from failed analysis or load attempts without leaving ambiguous repository graph state.

      [ ] 23.3.1.1 Subtask - Add coverage proving stale repository revision is surfaced explicitly after source changes.
      [ ] 23.3.1.2 Subtask - Add coverage proving refresh clears stale state and returns the graph to a coherent ready status.
      [ ] 23.3.1.3 Subtask - Add coverage proving failed analysis/load attempts preserve typed recovery information and bounded query behavior.

    [ ] 23.3.2 Task - End-to-end repository semantic workflow scenarios
      Prove the new pod works as a durable repository semantic service from setup through query without reintroducing a global knowledge subsystem.

      [ ] 23.3.2.1 Subtask - Add coverage proving one repository can analyze, load, refresh, and query its `source_code` graph end to end.
      [ ] 23.3.2.2 Subtask - Add coverage proving multiple repositories keep isolated local stores and `source_code` named graphs.
      [ ] 23.3.2.3 Subtask - Verify docs, contributor guidance, and repo-owned verification surfaces remain aligned with the final semantic graph architecture.
