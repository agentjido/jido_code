# Phase 31 - Memory Graph Product Hardening And Contributor Convergence

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/memory_ontology.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `README.md`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `priv/ontologies/jido-memory.ttl`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/source_code_graph/`
- `test/jido_code/`

## Relevant Assumptions / Defaults
- Phases 28 through 30 have added the runtime foundation, provenance capture seam, and durable memory adoption behavior.
- The remaining work is hardening, contributor convergence, and safe product-facing operational behavior.
- Memory capture and memory recall must remain explainable, bounded, and recoverable across repositories and revisions.

[x] 31 Phase 31 - Memory Graph Product Hardening And Contributor Convergence
  Harden the memory graph and capture plane so semantic memory becomes a durable product capability rather than a fragile experimental side layer.

  [x] 31.1 Section - Product Hardening And Recovery Convergence
    Strengthen operator- and workflow-facing memory behavior so stale, degraded, or recovering memory state remains legible and safe.

    [x] 31.1.1 Task - Harden bounded memory status and recovery behavior
      Standardize how memory freshness, invalidation, degradation, and recovery appear at product and workflow boundaries.

      [x] 31.1.1.1 Subtask - Standardize memory freshness, stale, invalidated, and recovery-required feedback across product-owned boundaries.
      [x] 31.1.1.2 Subtask - Ensure memory capture and query paths fail safely when repository memory state is unavailable or inconsistent.
      [x] 31.1.1.3 Subtask - Keep memory recovery actions repository-scoped and product-owned.

    [x] 31.1.2 Task - Harden cross-graph consistency and isolation
      Ensure the `source_code`, `memory`, and `workflow_provenance` graphs remain coherent and isolated per repository.

      [x] 31.1.2.1 Subtask - Verify stable cross-graph links remain consistent after refresh, restart, and recovery flows.
      [x] 31.1.2.2 Subtask - Ensure multi-repository memory state stays isolated even under shared runtime and verification flows.
      [x] 31.1.2.3 Subtask - Keep memory graph behavior explainable when code graph or provenance graph state is stale independently.

  [x] 31.2 Section - Contributor Workflow And Documentation Convergence
    Align docs and verification so contributors know how semantic memory is captured, validated, and kept safe over time.

    [x] 31.2.1 Task - Update contributor guidance for semantic memory
      Document the new write seam, ontology artifact, and adoption boundaries so contributors extend the memory system consistently.

      [x] 31.2.1.1 Subtask - Update README guidance for the repository semantic stack to include memory and workflow provenance.
      [x] 31.2.1.2 Subtask - Update contributor guidance to explain where provenance is inserted and where durable memory is adopted.
      [x] 31.2.1.3 Subtask - Clarify that raw runtime output is not durable memory without explicit classification or governed adoption.

    [x] 31.2.2 Task - Align verification paths with the memory stack
      Make repo-owned checks and test grouping reflect the new capture plane and memory graph architecture.

      [x] 31.2.2.1 Subtask - Add or update repo-owned verification aliases for memory graph and capture-plane behavior where needed.
      [x] 31.2.2.2 Subtask - Keep ontology, capture-plane, runtime, and durable-memory tests discoverable in contributor guidance.
      [x] 31.2.2.3 Subtask - Ensure memory graph verification remains compatible with existing repo quality and semantic verification flows.

  [x] 31.3 Section - Phase 31 Integration Tests
    Verify the final memory graph architecture is safe, explainable, and maintainable across runtime recovery, product behavior, and contributor workflows.

    [x] 31.3.1 Task - Product hardening scenarios
      Prove the memory graph remains bounded and recoverable under stale, degraded, restarted, and multi-repository conditions.

      [x] 31.3.1.1 Subtask - Add coverage proving memory status and recovery remain explicit across product and workflow boundaries.
      [x] 31.3.1.2 Subtask - Add coverage proving cross-graph links remain coherent after refresh and restart behavior.
      [x] 31.3.1.3 Subtask - Add coverage proving multi-repository memory behavior stays isolated and explainable.

    [x] 31.3.2 Task - Contributor and verification convergence scenarios
      Prove the semantic memory stack is documented and verifiable through normal contributor workflows.

      [x] 31.3.2.1 Subtask - Add coverage proving memory graph and capture-plane behavior are included in the intended verification paths.
      [x] 31.3.2.2 Subtask - Add coverage proving contributor guidance matches the final semantic memory architecture.
      [x] 31.3.2.3 Subtask - Verify the full spec workspace remains coherent after the memory graph roadmap is complete.
