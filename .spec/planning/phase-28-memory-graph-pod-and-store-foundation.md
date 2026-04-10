# Phase 28 - Memory Graph Pod And Store Foundation

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_ontology.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `priv/ontologies/jido-memory.ttl`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/source_code_graph.ex`
- `lib/jido_code/pods/`
- `lib/jido_code/actions/`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults
- The `source_code` graph capability already exists and owns the repository-local semantic store baseline.
- The next step is to add the runtime and storage foundation for `memory` and `workflow_provenance`, not yet full product adoption.
- The memory graph must reuse the repository-local semantic store rather than create a separate cross-repository memory service.
- Stable source-code IRIs remain the canonical anchors for memory and provenance links.

[ ] 28 Phase 28 - Memory Graph Pod And Store Foundation
  Establish the repository-scoped runtime, storage, ontology, and workspace boundaries needed before workflow provenance and durable memories can be inserted safely.

  [x] 28.1 Section - Memory Graph Runtime And Store Boundary
    Create the repository-scoped pod and store contract so the memory graph becomes a first-class sibling of the source-code graph inside the managed-repository kernel.

    [x] 28.1.1 Task - Introduce the repository-scoped MemoryGraph boundary
      Define the product-owned boundary helpers that fix canonical graph names, graph IRIs, ontology assets, and repository-local store paths for memory capability.

      [x] 28.1.1.1 Subtask - Add a repository-scoped memory graph boundary that names the `memory` and `workflow_provenance` graphs explicitly.
      [x] 28.1.1.2 Subtask - Reuse the repository-local TripleStore quad-store path shape already used by the semantic stack.
      [x] 28.1.1.3 Subtask - Ensure the boundary exposes stable base IRI helpers and ontology asset references for later capture and query work.

    [x] 28.1.2 Task - Add the MemoryGraphPod contract
      Define the pod, eager context state, and lazy specialist roles needed to record, query, validate, invalidate, and refresh repository memory state.

      [x] 28.1.2.1 Subtask - Add one repository-scoped MemoryGraphPod singleton per managed repository when the capability is enabled.
      [x] 28.1.2.2 Subtask - Define eager context metadata for graph names, revision state, latest validation status, and latest failure.
      [x] 28.1.2.3 Subtask - Define lazy recorder, querier, and validator specialist roles without yet introducing direct caller access to pod internals.

  [ ] 28.2 Section - Explicit Action And Workspace Surface
    Create the explicit action surface and bounded workspace entrypoints that will later back the memory capture plane.

    [ ] 28.2.1 Task - Introduce memory graph actions
      Define explicit actions for record, query, validate, invalidate, refresh, and status behavior rather than allowing direct graph writes or raw store access.

      [ ] 28.2.1.1 Subtask - Add explicit Jido actions for memory recording, recall, validation, invalidation, and refresh.
      [ ] 28.2.1.2 Subtask - Keep typed bounded outcomes for stale, degraded, disabled, and failure states.
      [ ] 28.2.1.3 Subtask - Ensure action contracts stay graph-aware but not UI-aware.

    [ ] 28.2.2 Task - Add AgentWorkspace entrypoints for memory capability
      Expose repository-scoped workspace entrypoints so product and workflow callers can prepare and inspect memory capability without learning pod topology.

      [ ] 28.2.2.1 Subtask - Add workspace entrypoints for ensuring the pod, retrieving status, and invoking bounded memory graph actions.
      [ ] 28.2.2.2 Subtask - Preserve explicit repo, workspace, actor, and revision context in workspace-owned contracts.
      [ ] 28.2.2.3 Subtask - Keep memory graph readiness, stale state, and recovery typed at the workspace boundary.

  [ ] 28.3 Section - Phase 28 Integration Tests
    Verify the new runtime and store foundation is repository-scoped, bounded, and coherent before workflow provenance capture begins.

    [ ] 28.3.1 Task - Pod and store foundation scenarios
      Prove the new memory graph capability is isolated per repository and aligned to the shared semantic store contract.

      [ ] 28.3.1.1 Subtask - Add coverage proving one MemoryGraphPod exists per enabled managed repository kernel.
      [ ] 28.3.1.2 Subtask - Add coverage proving `memory` and `workflow_provenance` are explicit named graphs in the repository-local quad store.
      [ ] 28.3.1.3 Subtask - Add coverage proving stable code-graph anchors remain available for later cross-graph links.

    [ ] 28.3.2 Task - Action and workspace boundary scenarios
      Prove callers can prepare and inspect memory capability only through bounded action and workspace contracts.

      [ ] 28.3.2.1 Subtask - Add coverage proving record/query/validate/invalidate/refresh route through explicit actions.
      [ ] 28.3.2.2 Subtask - Add coverage proving AgentWorkspace exposes typed bounded status and recovery behavior.
      [ ] 28.3.2.3 Subtask - Verify the spec workspace remains coherent after the memory graph runtime foundation lands.
