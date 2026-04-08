# Phase 21 - Full Ontology Analysis and Named Graph Load

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_pod.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `lib/jido_code/pods/`
- `lib/jido_code/agents/`
- `lib/jido_code/actions/`
- `lib/jido_code/agent_workspace.ex`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults
- Phase 20 has established the SourceCodeGraphPod contract, explicit action surface, and repository-scoped workspace boundary.
- `elixir-ontologies` full mode is the required semantic extraction profile.
- `triple_store` named-graph storage is the required local durability layer.
- The canonical graph name remains `source_code`.

[ ] 21 Phase 21 - Full Ontology Analysis and Named Graph Load
  Implement the full Elixir ontology analysis pipeline and coherent loading into the repository-local `source_code` named graph.

  [ ] 21.1 Section - Full-Mode Ontology Analysis Pipeline
    Wire the repository-scoped pod to ElixirOntologies so full-profile semantic extraction becomes a repeatable, explicit repository analysis step.

    [ ] 21.1.1 Task - Implement full-profile repository analysis action
      Build the action and supporting agent behavior that invokes ElixirOntologies full-mode extraction against a repository workspace.

      [ ] 21.1.1.1 Subtask - Configure full-profile analysis options explicitly rather than falling back to the light profile.
      [ ] 21.1.1.2 Subtask - Capture analysis outputs, metadata, and failure details in graph-context state.
      [ ] 21.1.1.3 Subtask - Persist revision metadata such as source commit or workspace snapshot identity with the analysis result.

    [ ] 21.1.2 Task - Normalize ontology analysis artifacts
      Turn raw analysis output into a stable intermediate representation suitable for coherent TripleStore ingestion.

      [ ] 21.1.2.1 Subtask - Define how ontology/schema triples and repository-specific individual triples are separated logically before load.
      [ ] 21.1.2.2 Subtask - Define how loadable RDF artifacts are staged for the `source_code` graph import.
      [ ] 21.1.2.3 Subtask - Define how analysis metadata remains accessible for later load diagnostics and refresh decisions.

  [ ] 21.2 Section - TripleStore Named Graph Load
    Load ontology schema and extracted project individuals into the local TripleStore database as one coherent repository-scoped named graph.

    [ ] 21.2.1 Task - Implement initial `source_code` graph load
      Build the explicit load path that creates or opens the local graph store and loads one coherent semantic snapshot into the canonical named graph.

      [ ] 21.2.1.1 Subtask - Initialize or open the repository-local TripleStore database with named-graph support.
      [ ] 21.2.1.2 Subtask - Load ontology/schema triples into the `source_code` named graph.
      [ ] 21.2.1.3 Subtask - Load repository-derived individual triples into the same `source_code` named graph as one semantic view.

    [ ] 21.2.2 Task - Implement coherent refresh semantics
      Ensure graph refresh replaces or rebuilds the repository semantic snapshot coherently so queries never observe a mixed revision.

      [ ] 21.2.2.1 Subtask - Define graph replacement or transactional rebuild semantics for `source_code`.
      [ ] 21.2.2.2 Subtask - Record latest successful load revision and timestamp in graph-context state.
      [ ] 21.2.2.3 Subtask - Expose typed load/refresh failure results that distinguish analysis failure from store failure.

  [ ] 21.3 Section - Product-Owned Load Entry Points
    Expose the new analysis and named-graph load behavior through the AgentWorkspace boundary so product-owned callers can drive semantic ingestion safely.

    [ ] 21.3.1 Task - Implement workspace analyze/load/refresh entrypoints
      Add the repository-scoped product APIs that ensure the pod exists and route to the explicit actions for semantic ingestion.

      [ ] 21.3.1.1 Subtask - Implement a repository-scoped analyze entrypoint that triggers full-mode ontology extraction.
      [ ] 21.3.1.2 Subtask - Implement a repository-scoped load entrypoint that loads the coherent `source_code` graph.
      [ ] 21.3.1.3 Subtask - Implement a repository-scoped refresh entrypoint that rebuilds the graph coherently.

    [ ] 21.3.2 Task - Implement load-status visibility
      Keep load state explainable to product callers by exposing graph revision, readiness, and latest failure at the workspace boundary.

      [ ] 21.3.2.1 Subtask - Add a status entrypoint for graph readiness and latest imported revision.
      [ ] 21.3.2.2 Subtask - Add typed not-loaded and stale-revision responses for callers that depend on semantic graph readiness.
      [ ] 21.3.2.3 Subtask - Ensure callers receive bounded product-shaped status rather than raw TripleStore or ElixirOntologies internals.

  [ ] 21.4 Section - Phase 21 Integration Tests
    Verify that repository analysis runs in full ontology mode and that the resulting graph is loaded into a coherent `source_code` named graph for one managed repository.

    [ ] 21.4.1 Task - Full ontology analysis scenarios
      Prove semantic extraction runs with the intended profile and produces loadable repository-scoped graph artifacts.

      [ ] 21.4.1.1 Subtask - Add coverage proving full-mode analysis is selected explicitly and not downgraded to light mode.
      [ ] 21.4.1.2 Subtask - Add coverage proving ontology/schema and project individual material are both produced for load.
      [ ] 21.4.1.3 Subtask - Add coverage proving analysis metadata records repository revision and failure state cleanly.

    [ ] 21.4.2 Task - Named-graph load and refresh scenarios
      Prove the repository-local TripleStore database receives one coherent `source_code` graph and that refresh replaces it cleanly.

      [ ] 21.4.2.1 Subtask - Add coverage proving the initial load writes to the canonical `source_code` named graph.
      [ ] 21.4.2.2 Subtask - Add coverage proving ontology/schema and project individuals are queryable as one semantic snapshot after load.
      [ ] 21.4.2.3 Subtask - Add coverage proving refresh does not leave mixed graph revisions visible.
