# Phase 20 - Source Code Graph Pod Foundation

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/agent_os_integration.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `../specs/package.spec.md`
- `../specs/product_foundation_docs.spec.md`
- `../decisions/jido_code.jido_agent_os_integration.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_os.ex`
- `lib/jido_code/pods/`
- `lib/jido_code/agents/`
- `lib/jido_code/actions/`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults
- Phase 19 establishes the repository-scoped kernel model and current pod topology for AgentOS-backed work in `jido_code`.
- The source-code graph capability is repository-scoped and should live beside `RepoPod` and `CodingPod`, not as a revived cross-repository knowledge service.
- `elixir-ontologies` is the canonical Elixir-aware ontology analysis dependency and shall be used in full extraction mode.
- `triple_store` is the canonical local RDF store and named-graph database for this capability.
- The canonical named graph is `source_code`.

[ ] 20 Phase 20 - Source Code Graph Pod Foundation
  Establish the repository-scoped SourceCodeGraphPod contract, state ownership model, and explicit action surfaces needed for full-mode ontology analysis and named-graph ingestion.

  [x] 20.1 Section - Pod Contract and Runtime Boundaries
    Define the pod, state, and repository-scoped runtime ownership model so the semantic source-code graph capability fits the existing AgentOS kernel topology without reviving an ambient service.

    [x] 20.1.1 Task - Define the repository-scoped pod topology
      Introduce the SourceCodeGraphPod as a managed-repo singleton with eager context/state ownership and lazy specialist agents.

      [x] 20.1.1.1 Subtask - Create `JidoCode.Pods.SourceCodeGraphPod` as one optional singleton per ManagedRepo kernel.
      [x] 20.1.1.2 Subtask - Define one eager graph-context agent that owns workspace path, graph-store path, graph name, ontology profile, revision metadata, and latest import status.
      [x] 20.1.1.3 Subtask - Define lazy specialist agents for ontology analysis, named-graph load/refresh, and SPARQL query execution.

    [x] 20.1.2 Task - Define workspace and store boundary ownership
      Make the repository workspace path, local graph-store location, and graph identity explicit so later phases can load and query a durable repository-local source graph safely.

      [x] 20.1.2.1 Subtask - Define how the pod resolves the managed-repo workspace path from product-owned repository context.
      [x] 20.1.2.2 Subtask - Define the local TripleStore database path and per-repository storage isolation rules.
      [x] 20.1.2.3 Subtask - Define stable naming for the `source_code` graph and any repository-local dataset metadata that accompanies it.

  [ ] 20.2 Section - Explicit Action Surface
    Define the explicit tools that agents will use so analyze, ingest, refresh, and query behavior remains traceable and testable.

    [ ] 20.2.1 Task - Define ontology analysis and ingestion actions
      Introduce the explicit actions that run ElixirOntologies full-mode analysis and load the resulting graph into the local TripleStore database.

      [ ] 20.2.1.1 Subtask - Define an action for full-profile ontology analysis over a repository workspace.
      [ ] 20.2.1.2 Subtask - Define an action for loading ontology/schema and extracted individuals into the `source_code` named graph.
      [ ] 20.2.1.3 Subtask - Define an action for coherent graph refresh that replaces the named graph rather than layering partial revisions.

    [ ] 20.2.2 Task - Define query and status actions
      Introduce the explicit actions that inspect graph readiness and execute post-load semantic queries for pod agents.

      [ ] 20.2.2.1 Subtask - Define an action for graph status and latest import metadata.
      [ ] 20.2.2.2 Subtask - Define an action for SPARQL query execution over the loaded `source_code` graph.
      [ ] 20.2.2.3 Subtask - Define any bounded helper actions for graph revision lookup, dataset inspection, or load health diagnostics.

  [ ] 20.3 Section - Product-Owned Workspace Integration
    Update the product-owned AgentWorkspace boundary so repository entrypoints can ensure and route to the source-code graph pod without exposing pod topology details.

    [ ] 20.3.1 Task - Extend AgentWorkspace with source-code graph entrypoints
      Add the repository-scoped workspace APIs needed to ensure the pod exists and trigger analyze, load, refresh, and query behavior.

      [ ] 20.3.1.1 Subtask - Define `ensure_source_code_graph_pod/2` or equivalent repository-scoped pod lifecycle entrypoint.
      [ ] 20.3.1.2 Subtask - Define product-owned entrypoints for analyze/load/refresh behavior that hide pod internals.
      [ ] 20.3.1.3 Subtask - Define a product-owned query entrypoint that returns structured semantic query results rather than pod-native internals.

    [ ] 20.3.2 Task - Define capability gating and failure shaping
      Keep the new graph capability bounded and explainable by making enablement, readiness, and failure semantics explicit at the workspace boundary.

      [ ] 20.3.2.1 Subtask - Define enablement behavior for repositories where the semantic source-code graph is not configured or not yet loaded.
      [ ] 20.3.2.2 Subtask - Define typed failure outcomes for ontology analysis, graph load, and query attempts.
      [ ] 20.3.2.3 Subtask - Define how graph readiness and degradation remain repository-scoped rather than becoming global product state.

  [ ] 20.4 Section - Phase 20 Integration Tests
    Verify the new SourceCodeGraphPod contract fits the existing repository-scoped AgentOS model and exposes explicit, product-owned entrypoints without ambient graph coupling.

    [ ] 20.4.1 Task - Repository-scoped pod contract scenarios
      Prove the source-code graph capability is owned per repository kernel and does not leak as a singleton service or work-item-scoped pod.

      [ ] 20.4.1.1 Subtask - Add coverage proving one managed repository can host a SourceCodeGraphPod without affecting another repository kernel.
      [ ] 20.4.1.2 Subtask - Add coverage proving the pod is singleton-per-repository when enabled and not multiplied per WorkItem.
      [ ] 20.4.1.3 Subtask - Add coverage proving AgentWorkspace hides the pod topology from product callers.

    [ ] 20.4.2 Task - Explicit action and boundary scenarios
      Prove analyze/load/query behavior is represented by explicit tools and typed workspace entrypoints rather than hidden helper calls.

      [ ] 20.4.2.1 Subtask - Add coverage proving the action set for analyze, load, refresh, and query is explicit and schema-driven.
      [ ] 20.4.2.2 Subtask - Add coverage proving disabled or not-ready graph states surface as typed workspace outcomes.
      [ ] 20.4.2.3 Subtask - Verify the current product and spec workspace remain coherent after adding the new pod contract.
