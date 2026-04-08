# Phase 22 - Source Code Graph Query Agents and Workflow Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_pod.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/pods/`
- `lib/jido_code/agents/`
- `lib/jido_code/actions/`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults
- Phase 21 has already established a repository-local TripleStore dataset with a coherent `source_code` named graph.
- SPARQL query execution should use the `sparql` library as the canonical query surface.
- Semantic query remains an explicit tool flow for pod-local agents, not an ambient side channel.

[ ] 22 Phase 22 - Source Code Graph Query Agents and Workflow Adoption
  Add SPARQL-backed query tools and specialist agents to the SourceCodeGraphPod, then expose repository-scoped semantic query behavior through product-owned workspace entrypoints and pod workflows.

  [x] 22.1 Section - SPARQL Query Action Surface
    Implement the explicit query tools that let repository-scoped agents interrogate the loaded `source_code` graph through a stable SPARQL boundary.

    [x] 22.1.1 Task - Implement SPARQL-backed query action
      Build the canonical query action that validates and runs graph queries against the loaded `source_code` graph.

      [x] 22.1.1.1 Subtask - Use the `sparql` library as the canonical SPARQL surface for parsing or constructing repository graph queries.
      [x] 22.1.1.2 Subtask - Route query execution against the repository-local TripleStore dataset and `source_code` named graph.
      [x] 22.1.1.3 Subtask - Return structured result rows and query metadata without leaking raw store internals.

    [x] 22.1.2 Task - Implement bounded semantic helper actions
      Add reusable higher-level actions that sit on top of SPARQL for common source-code graph workflows without hiding the underlying explicit query contract.

      [x] 22.1.2.1 Subtask - Define helper actions for module/function/runtime-pattern lookups that compile to explicit SPARQL queries.
      [x] 22.1.2.2 Subtask - Define helper actions for impact-style traversals over semantic relationships when those are common agent needs.
      [x] 22.1.2.3 Subtask - Define typed query failure and empty-result behavior for pod agents and product-owned callers.

  [ ] 22.2 Section - Specialist Agent Adoption
    Add the lazy specialist agents that perform semantic graph analysis, refresh, and query work inside the SourceCodeGraphPod.

    [ ] 22.2.1 Task - Implement the graph specialist agents
      Build the pod-local agents that own analysis, load, and query behavior over the repository semantic graph.

      [ ] 22.2.1.1 Subtask - Implement an ontology-analysis specialist agent that drives full-mode repository analysis.
      [ ] 22.2.1.2 Subtask - Implement a graph-loader specialist agent that drives initial load and coherent refresh of `source_code`.
      [ ] 22.2.1.3 Subtask - Implement a semantic-query specialist agent that runs SPARQL-backed graph questions for other pod or product flows.

    [ ] 22.2.2 Task - Add query tools to interested coding flows
      Let selected repository or coding specialists consult the source-code graph explicitly once it exists, without making semantic lookup an ambient dependency.

      [ ] 22.2.2.1 Subtask - Define which existing repository or coding agents may receive semantic query tools through explicit composition.
      [ ] 22.2.2.2 Subtask - Preserve repository-scoped gating so those tools only run when the semantic graph is enabled and ready.
      [ ] 22.2.2.3 Subtask - Keep semantic queries as explicit tool calls in prompts and activity history rather than hidden helper behavior.

  [ ] 22.3 Section - Product Workflow Entry Points
    Expose semantic graph query and refresh behavior through product-owned workspace APIs so the pod can be used by higher-level workflows without leaking topology.

    [ ] 22.3.1 Task - Implement repository-scoped query entrypoints
      Add product-facing query APIs that ensure the pod is ready and route semantic lookups safely.

      [ ] 22.3.1.1 Subtask - Implement a workspace query entrypoint that targets the `source_code` graph for one managed repository.
      [ ] 22.3.1.2 Subtask - Implement repository-scoped helper entrypoints for common semantic lookup flows if needed.
      [ ] 22.3.1.3 Subtask - Preserve typed not-loaded, disabled, and query-failed outcomes at the workspace boundary.

    [ ] 22.3.2 Task - Integrate semantic graph use into repository workflows
      Make the new capability available to repository-scoped workflows where it adds value without reintroducing old ambient graph assumptions.

      [ ] 22.3.2.1 Subtask - Define which repository workflows should ensure or refresh the graph explicitly before semantic query.
      [ ] 22.3.2.2 Subtask - Define how semantic query results feed planning, review, or explanation flows as bounded inputs.
      [ ] 22.3.2.3 Subtask - Keep product truth in managed-repo and governed-run records even when workflows consult semantic graph state.

  [ ] 22.4 Section - Phase 22 Integration Tests
    Verify that pod-local agents can query the loaded `source_code` graph through the SPARQL action surface and that product-owned workspace entrypoints expose bounded repository-scoped semantic queries.

    [ ] 22.4.1 Task - SPARQL query scenarios
      Prove the repository semantic graph is queryable through the canonical SPARQL tool surface after load.

      [ ] 22.4.1.1 Subtask - Add coverage proving query actions use the `sparql` library and target the repository-local `source_code` graph.
      [ ] 22.4.1.2 Subtask - Add coverage proving structured result rows are returned for representative module/function/runtime queries.
      [ ] 22.4.1.3 Subtask - Add coverage proving query failures and not-ready states stay typed and bounded.

    [ ] 22.4.2 Task - Pod and workflow adoption scenarios
      Prove specialist agents and repository-scoped workspace entrypoints can use the semantic graph without leaking pod internals or ambient graph coupling.

      [ ] 22.4.2.1 Subtask - Add coverage proving SourceCodeGraphPod specialist agents can analyze, refresh, and query one repository graph.
      [ ] 22.4.2.2 Subtask - Add coverage proving repository-scoped workspace entrypoints hide pod topology details.
      [ ] 22.4.2.3 Subtask - Add coverage proving selected higher-level workflows consult the semantic graph only through explicit bounded entrypoints.
