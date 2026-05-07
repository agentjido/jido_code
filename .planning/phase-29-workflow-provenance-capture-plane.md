# Phase 29 - Workflow Provenance Capture Plane

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_workspace/`
- `lib/jido_code/source_code_graph/workflow_service.ex`
- `lib/jido_code/source_code_graph/governed_adoption.ex`
- `test/jido_code/agent_workspace_test.exs`
- `test/jido_code/agent_os_integration_test.exs`

## Relevant Assumptions / Defaults
- Phase 28 has established the MemoryGraphPod, shared semantic-store ownership, and explicit action/workspace entrypoints.
- The next step is to define how runtime and workflow events become individuals in `workflow_provenance`.
- Runtime and workflow callers should emit typed capture envelopes, not raw RDF triples.
- Work session and provenance insertion must only happen when repo, actor, workspace, and revision context are explicit.

[x] 29 Phase 29 - Workflow Provenance Capture Plane
  Add the bounded capture seam that records workflow provenance into `workflow_provenance` at runtime and workflow boundaries without turning every intermediate model artifact into durable memory.

  [x] 29.1 Section - Capture Envelope And Writer Boundary
    Define the canonical capture request shape and writer behavior that turns bounded runtime/workflow events into ontology-aligned provenance individuals.

    [x] 29.1.1 Task - Introduce typed capture envelopes
      Create the typed envelope format that callers must emit instead of writing raw triples directly.

      [x] 29.1.1.1 Subtask - Define capture envelope shapes for WorkSession, AgentRun, ToolInvocation, PromptTurn, Plan, Patch, and Review provenance.
      [x] 29.1.1.2 Subtask - Require repository, actor, workspace, and revision context on provenance capture requests.
      [x] 29.1.1.3 Subtask - Keep the capture request model separate from raw ontology serialization details.

    [x] 29.1.2 Task - Add the canonical provenance writer boundary
      Build the writer layer that accepts capture envelopes and inserts ontology-aligned individuals into `workflow_provenance`.

      [x] 29.1.2.1 Subtask - Route provenance writes through the canonical memory capture plane rather than direct store access.
      [x] 29.1.2.2 Subtask - Ensure inserted provenance links back to stable `source_code` graph anchors when code entities are known.
      [x] 29.1.2.3 Subtask - Preserve bounded failure, stale, and recovery behavior at the writer boundary.

  [x] 29.2 Section - Runtime And Workflow Insertion Seams
    Connect the capture plane to the real runtime and workflow boundaries where provenance should be created over time.

    [x] 29.2.1 Task - Emit provenance from AgentWorkspace runtime boundaries
      Make AgentWorkspace the canonical place where repository-scoped runtime work starts and therefore where workflow provenance begins.

      [x] 29.2.1.1 Subtask - Record WorkSession and AgentRun provenance when bounded planning, execution, review, explanation, and semantic workflow work begins.
      [x] 29.2.1.2 Subtask - Record tool, plan, patch, and review provenance around specialist execution without leaking specialist internals into callers.
      [x] 29.2.1.3 Subtask - Ensure resumable and recovered runtime paths continue to emit bounded provenance consistently.

    [x] 29.2.2 Task - Emit provenance from product-owned workflow boundaries
      Ensure product-owned workflow services can extend provenance capture without bypassing the canonical runtime seam.

      [x] 29.2.2.1 Subtask - Allow workflow services to emit bounded capture envelopes for semantic workflow preparation and governed adoption steps.
      [x] 29.2.2.2 Subtask - Keep workflow provenance insertion in `workflow_provenance`, not `memory`.
      [x] 29.2.2.3 Subtask - Explicitly reject transient helper output or unadopted model text as durable memory at this stage.

  [x] 29.3 Section - Phase 29 Integration Tests
    Verify the new capture plane records provenance at the intended seams and stays bounded under normal, resumed, and failed runtime conditions.

    [x] 29.3.1 Task - Capture envelope and writer scenarios
      Prove provenance insertion uses the capture plane rather than raw graph access.

      [x] 29.3.1.1 Subtask - Add coverage proving typed provenance envelopes become ontology-aligned individuals in `workflow_provenance`.
      [x] 29.3.1.2 Subtask - Add coverage proving capture requests fail safely when required repo, actor, workspace, or revision context is missing.
      [x] 29.3.1.3 Subtask - Add coverage proving raw direct triple-writing is not required by runtime or workflow callers.

    [x] 29.3.2 Task - Runtime and workflow seam scenarios
      Prove provenance is inserted at the real runtime and product workflow boundaries where it belongs.

      [x] 29.3.2.1 Subtask - Add coverage proving AgentWorkspace emits WorkSession and AgentRun provenance for bounded work entrypoints.
      [x] 29.3.2.2 Subtask - Add coverage proving tool, plan, patch, and review activity remains workflow provenance rather than durable memory.
      [x] 29.3.2.3 Subtask - Verify the spec workspace remains coherent after workflow provenance capture lands.
